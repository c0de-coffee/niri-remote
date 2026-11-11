//! plasma-login-manager's greeter protocol, so KDE's own login screen (`plasma-login-greeter`)
//! works as the remote login screen.
//!
//! The greeter finds the socket in `SDDM_SOCKET`. Messages are Qt `QDataStream`s with no framing:
//! a big-endian `quint32` message type, then its arguments; a `QString` is a big-endian `quint32`
//! byte count (`0xffffffff` for a null string) followed by UTF-16BE. From
//! plasma-login-manager 6.8 (`src/common/Messages.h`, `GreeterProxy.cpp`, `SocketServer.cpp`):
//!
//! - greeter → us: `Connect` (0), `Login` (1) with user, password, session type (`quint32`) and
//!   session file name
//! - us → greeter: `LoginSucceeded` (0), `LoginFailed` (1), `InformationMessage` (2) with a string
//!
//! A login is one request with the password, so we drive the greetd-style conversation with
//! remote-dm ourselves (`GreeterRequest`s, like `greeter_ipc` does for greetd greeters) and answer
//! the PAM prompts from what the greeter sent. The greeter's session choice is ignored, remote-dm
//! starts the configured session command.
//!
//! The greeter can't answer the "already logged in here, log that out?" question, so it becomes a
//! failed login with a message, and logging in as the same user again within a minute is the yes.

use std::time::{Duration, Instant};

use anyhow::Context as _;
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::UnixStream;
use tokio::sync::{mpsc, oneshot};

use crate::greeter_ipc::{GreeterRequest, Request, Response};
use crate::worker::PromptKind;

const CONNECT: u32 = 0;
const LOGIN: u32 = 1;

const LOGIN_SUCCEEDED: u32 = 0;
const LOGIN_FAILED: u32 = 1;
const INFORMATION_MESSAGE: u32 = 2;

/// Longer strings aren't legitimate (in bytes of UTF-16).
const MAX_STRING: u32 = 16 * 1024;

/// How long a second login confirms logging out the user's other sessions.
const CONFIRM_TIMEOUT: Duration = Duration::from_secs(60);

pub async fn serve(
    mut stream: UnixStream,
    remote: u64,
    requests: mpsc::UnboundedSender<GreeterRequest>,
) -> anyhow::Result<()> {
    let mut conversation = Conversation {
        remote,
        requests,
        confirmed: None,
    };
    loop {
        match stream.read_u32().await? {
            CONNECT => tracing::debug!(remote, "plasma greeter connected"),
            LOGIN => {
                let user = read_string(&mut stream).await?;
                let password = read_string(&mut stream).await?;
                let session_type = stream.read_u32().await?;
                let session_file = read_string(&mut stream).await?;
                tracing::debug!(remote, user, session_type, session_file, "plasma greeter login");

                let mut out = Vec::new();
                match conversation.login(&user, password).await? {
                    Ok(()) => out.extend(LOGIN_SUCCEEDED.to_be_bytes()),
                    Err(message) => {
                        out.extend(LOGIN_FAILED.to_be_bytes());
                        // After LoginFailed: the greeter replaces the message with "Login
                        // Failed" on failure, but keeps one that comes after.
                        if let Some(message) = message {
                            out.extend(INFORMATION_MESSAGE.to_be_bytes());
                            write_string(&mut out, &message);
                        }
                    }
                }
                stream.write_all(&out).await?;
                stream.flush().await?;
            }
            other => anyhow::bail!("unknown message {other}"),
        }
    }
}

struct Conversation {
    remote: u64,
    requests: mpsc::UnboundedSender<GreeterRequest>,
    /// The user asked to confirm logging out their other sessions, and when.
    confirmed: Option<(String, Instant)>,
}

impl Conversation {
    async fn ask(&self, request: Request) -> anyhow::Result<Response> {
        let (reply, response) = oneshot::channel();
        self.requests
            .send(GreeterRequest {
                remote: self.remote,
                request,
                reply,
            })
            .context("shutting down")?;
        Ok(response
            .await
            .unwrap_or_else(|_| Response::error("the session went away")))
    }

    /// Logs `user` in. The inner error is the message to show, if any.
    async fn login(&mut self, user: &str, password: String) -> anyhow::Result<Result<(), Option<String>>> {
        // Whatever an earlier attempt left behind.
        self.ask(Request::CancelSession).await?;

        let confirmed = self
            .confirmed
            .take()
            .is_some_and(|(name, at)| name == user && at.elapsed() < CONFIRM_TIMEOUT);

        let mut password = Some(password);
        let mut response = self
            .ask(Request::CreateSession {
                username: user.to_owned(),
            })
            .await?;
        loop {
            let answer = match response {
                Response::Success => break,
                Response::Error { description, .. } => {
                    tracing::debug!(remote = self.remote, "plasma greeter login failed: {description}");
                    return Ok(Err(None));
                }
                Response::AuthMessage {
                    auth_message_type,
                    auth_message,
                } => match auth_message_type {
                    PromptKind::Secret => match password.take() {
                        Some(password) => Some(password),
                        // A second secret prompt (a new password, say): the greeter can't ask.
                        None => return self.give_up(auth_message).await,
                    },
                    PromptKind::Visible if auth_message == crate::conflict_question(user) => {
                        if confirmed {
                            Some("yes".to_owned())
                        } else {
                            self.ask(Request::PostAuthMessageResponse {
                                response: Some("no".to_owned()),
                            })
                            .await?;
                            self.confirmed = Some((user.to_owned(), Instant::now()));
                            return Ok(Err(Some(crate::conflict_retry_message(user))));
                        }
                    }
                    PromptKind::Visible => return self.give_up(auth_message).await,
                    PromptKind::Info | PromptKind::Error => {
                        tracing::debug!(remote = self.remote, "PAM message: {auth_message}");
                        None
                    }
                },
            };
            response = self
                .ask(Request::PostAuthMessageResponse { response: answer })
                .await?;
        }

        match self
            .ask(Request::StartSession {
                cmd: Vec::new(),
                env: Vec::new(),
            })
            .await?
        {
            Response::Success => Ok(Ok(())),
            Response::Error { description, .. } => Ok(Err(Some(description))),
            Response::AuthMessage { .. } => Ok(Err(None)),
        }
    }

    /// Ends a login that needs something the greeter can't ask for, showing what PAM asked.
    async fn give_up(&self, message: String) -> anyhow::Result<Result<(), Option<String>>> {
        self.ask(Request::CancelSession).await?;
        Ok(Err(Some(message)))
    }
}

async fn read_string(stream: &mut UnixStream) -> anyhow::Result<String> {
    let len = stream.read_u32().await?;
    if len == u32::MAX {
        return Ok(String::new());
    }
    anyhow::ensure!(len <= MAX_STRING && len % 2 == 0, "bad string length {len}");
    let mut bytes = vec![0; len as usize];
    stream.read_exact(&mut bytes).await?;
    let units: Vec<u16> = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|unit| u16::from_be_bytes(*unit))
        .collect();
    String::from_utf16(&units).context("bad UTF-16")
}

fn write_string(out: &mut Vec<u8>, s: &str) {
    let units: Vec<u16> = s.encode_utf16().collect();
    out.extend(((units.len() * 2) as u32).to_be_bytes());
    for unit in units {
        out.extend(unit.to_be_bytes());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qstring_encoding() {
        let mut out = Vec::new();
        write_string(&mut out, "中a");
        assert_eq!(out, [0, 0, 0, 4, 0x4e, 0x2d, 0, b'a']);
    }
}
