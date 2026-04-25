# TODO / Planned Features

## 1. Auto VM launch with managed tmux session
On kernel boot, automatically allocate free SSH/GDB ports, start the VM in a
detached tmux session named after the kernel/build, and run it in the
background. Provide helpers to attach, list, and stop these sessions.

## 2. Named envsetup profiles
Save recent `envsetup.sh` invocations (e.g. `SRC=... OBJ=... ARCH=...`) as
reusable profiles with an alias and an auto-assigned id. Allow re-applying a
profile by alias, by id, or via an interactive picker (fzf-style).
