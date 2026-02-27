python sys.path.insert(0, "/opt/gef"); from gef import *; Gef.main()

# configs
set history size unlimited

# useful shortcuts
alias cxz=context
alias bb=brva
alias dsa=disass
alias tre=thread
alias itre=info thread
alias pp=p*

# custom commands
define view_code
    gef config context.layout "legend source mem_access trace threads extra"
    gef config context_source.nb_lines 23
end

define view_gef
    gef config context.layout "legend regs stack code args source mem_access threads trace extra"
    gef config context_code.nb_lines 6
end

define view_zero
    gef config context.layout ""
end

# debugging symbol server
set debuginfod url https://debuginfod.ubuntu.com
set debuginfod enabled on

# bata24/gef: kernel debugging helper
define kernel
target remote:$arg0
python
import gdb
gdb.execute("ksymaddr-remote --vmlinux-file " + gdb.current_progspace().filename)
end
end

python
import gdb

class BTFileLineFunc(gdb.Command):
    """Backtrace showing frame#, source file:line and function name, highlighting selected frame."""
    def __init__(self):
        super(BTFileLineFunc, self).__init__("btt", gdb.COMMAND_STACK)

    def invoke(self, arg, from_tty):
        limit = 20
        if arg:
            try:
                limit = int(arg)
            except ValueError:
                gdb.write("Argument must be a number.\n")
                return

        try:
            sel_level = gdb.selected_frame().level()
        except Exception:
            sel_level = None

        frame = gdb.newest_frame()
        idx = 0
        while frame:
            if limit != -1 and idx >= limit:
                break

            sal = frame.find_sal()
            if sal.symtab:
                filename = sal.symtab.filename
                line = sal.line
            else:
                filename = "??"
                line = "?"
            func = frame.name() or "??"

            if idx == sel_level:
                gdb.write(f"[=>#{idx:<2}] {filename}:{line}, <{func}>\n")
            else:
                gdb.write(f"[  #{idx:<2}] {filename}:{line}, <{func}>\n")

            frame = frame.older()
            idx += 1

BTFileLineFunc()

class BTRCommand(gdb.Command):
    """
    btr [count]
    Backtrace Tree: display stack frames in caller->callee order as a tree.
    """

    def __init__(self):
        super(BTRCommand, self).__init__("btr", gdb.COMMAND_STACK)

    def invoke(self, arg, from_tty):
        frames = []
        frame = gdb.newest_frame()
        while frame:
            frames.append(frame)
            frame = frame.older()

        call_path = list(reversed(frames))

        if arg:
            try:
                val = int(arg)
                if val > 0:
                    if val < len(call_path):
                        call_path = call_path[-val:]
                elif val < 0:
                    skip = abs(val)
                    if skip < len(call_path):
                        call_path = call_path[skip:]
                    else:
                        gdb.write("Skipped all frames.\n")
                        return
            except ValueError:
                gdb.write("Argument must be a number.\n")
                return

        for i, f in enumerate(call_path):
            func_name = f.name() or "??"
            if i == 0:
                prefix = ""
            else:
                padding = "   " * (i - 1)
                prefix = f"{padding}|_ "
            gdb.write(f"{prefix}{func_name}\n")

BTRCommand()
end

