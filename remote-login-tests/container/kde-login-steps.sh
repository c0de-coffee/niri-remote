# Sourced by the host before kde-login-shot.sh: xdotool steps for regreet at 1280x720.
# Cancel (only there if regreet pre-filled a user), edit the user name, type it, Login.
LOGIN_USER="xdotool mousemove 760 444 click 1; sleep 1; xdotool mousemove 871 329 click 1; sleep 0.7; xdotool mousemove 670 329 click 1; sleep 0.5; xdotool key ctrl+a; xdotool type --delay 60 rltest; sleep 0.3; xdotool mousemove 853 444 click 1"
LOGIN_PASSWORD="xdotool type --delay 60 rltest; xdotool key Return"
