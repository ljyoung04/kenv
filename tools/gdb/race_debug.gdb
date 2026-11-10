# Kernel race-condition debugging helpers: `kidnap` / `restore`
#
# Prerequisites:
#   - GEF (bata24 fork) already loaded in this gdb session.
#     (i.e. `from gef import *; Gef.main()` ran earlier in .gdbinit)
#   - qemu-system kernel debugging target.
#
# Usage (in ~/.gdbinit, AFTER the GEF load line):
#   source /path/to/race_debug.gdb
#
# Commands:
#   kidnap [ADDR]   save current vCPU's $pc and park it on `eb fe` (jmp 0).
#                   ADDR: optional explicit trap address (must be `eb fe`).
#                         if omitted, search kernel r-x pages.
#   restore         restore $pc saved by kidnap on the current vCPU (GDB thread).

python
import gdb
import re as _re_kidnap

# {gdb_thread.num: original_pc}
_KIDNAP_SAVED_RIP = {}
_KIDNAP_LAST_TRAP = None


def _kidnap_find_trap_addr():
    """Locate an `eb fe` byte sequence in kernel executable pages via GEF's
    search-pattern. Returns int addr or None."""
    out = gdb.execute(
        "search-pattern --hex 'eb fe' -k -p r?x -l 1 -Q -S",
        to_string=True,
    )
    for line in out.splitlines():
        m = _re_kidnap.match(r"\s*(0x[0-9a-fA-F]+):", line)
        if m:
            return int(m.group(1), 16)
    return None


def _kidnap_verify_trap(addr):
    """Return True iff `addr` actually contains the bytes `eb fe`."""
    try:
        data = read_memory(addr, 2)
    except Exception as e:
        err("read_memory({:#x}, 2) failed: {}".format(addr, e))
        return False
    return data == b"\xeb\xfe"


class KidnapCommand(gdb.Command):
    """Trap the current vCPU in an infinite loop (kernel race debugging helper).

Syntax: kidnap [ADDR]

  ADDR   explicit trap address; must contain bytes `eb fe`.
         if omitted, search kernel r-x pages for one.

Per-thread (vCPU) original RIP is saved so `restore` can undo.
Requires qemu-system kernel debugging.
"""

    def __init__(self):
        super().__init__("kidnap", gdb.COMMAND_USER)

    def invoke(self, args, from_tty):
        global _KIDNAP_LAST_TRAP
        self.dont_repeat()
        try:
            argv = gdb.string_to_argv(args)
            if len(argv) > 1:
                err("usage: kidnap [ADDR]")
                return

            if not is_qemu_system():
                err("kidnap requires qemu-system kernel debugging")
                return

            thread = gdb.selected_thread()
            if thread is None:
                err("No selected thread")
                return

            if thread.num in _KIDNAP_SAVED_RIP:
                warn("thread {} is already kidnapped (orig pc = {:#x}). "
                     "Use `restore` first.".format(
                         thread.num, _KIDNAP_SAVED_RIP[thread.num]))
                return

            if argv:
                try:
                    trap = int(gdb.parse_and_eval(argv[0]))
                except (gdb.error, ValueError) as e:
                    err("invalid address '{}': {}".format(argv[0], e))
                    return
                if not _kidnap_verify_trap(trap):
                    err("{:#x} is not an infinite loop (expected bytes: eb fe)".format(trap))
                    return
                info("using user-provided trap {:#x}".format(trap))
            else:
                trap = _kidnap_find_trap_addr()
                if trap is None:
                    err("failed to find `eb fe` in kernel r-x pages")
                    return
                if not _kidnap_verify_trap(trap):
                    err("found {:#x} but re-read mismatched; aborting".format(trap))
                    return
                ok("found kernel trap (eb fe) at {:#x}".format(trap))
                _KIDNAP_LAST_TRAP = trap

            orig_pc = int(current_arch.pc)
            _KIDNAP_SAVED_RIP[thread.num] = orig_pc
            gdb.execute("set $pc = {:#x}".format(trap))
            ok("thread {} kidnapped: pc {:#x} -> {:#x}".format(
                thread.num, orig_pc, trap))
        except Exception as e:
            err("kidnap failed: {}".format(e))


class RestoreCommand(gdb.Command):
    """Restore RIP saved by `kidnap` on the current vCPU.

Syntax: restore

Restores pc stored by `kidnap` for the currently selected GDB thread (vCPU).
"""

    def __init__(self):
        super().__init__("restore", gdb.COMMAND_USER)

    def invoke(self, args, from_tty):
        self.dont_repeat()
        try:
            if not is_qemu_system():
                err("restore requires qemu-system kernel debugging")
                return

            thread = gdb.selected_thread()
            if thread is None:
                err("No selected thread")
                return

            if thread.num not in _KIDNAP_SAVED_RIP:
                err("thread {} has no saved pc (not kidnapped?)".format(thread.num))
                return

            cur_pc = int(current_arch.pc)
            orig_pc = _KIDNAP_SAVED_RIP.pop(thread.num)
            gdb.execute("set $pc = {:#x}".format(orig_pc))
            ok("thread {} restored: pc {:#x} -> {:#x}".format(
                thread.num, cur_pc, orig_pc))
        except Exception as e:
            err("restore failed: {}".format(e))


KidnapCommand()
RestoreCommand()
end
