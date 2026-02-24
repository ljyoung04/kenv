T=/sys/kernel/debug/tracing

# Clear trace buffer
alias tclear='echo > $T/trace'

# Tracing on/off
alias ton='echo 1 > $T/tracing_on'
alias toff='echo 0 > $T/tracing_on'

# View trace output
alias tcat='cat $T/trace_pipe'

# Stacktrace on/off
alias tstack='echo 1 > $T/options/stacktrace'
alias tnostack='echo 0 > $T/options/stacktrace'

# kmem events on/off
alias tkmem='echo 1 > $T/events/kmem/enable'
alias tnokmem='echo 0 > $T/events/kmem/enable'

# Set target process name (once)
ttarget() {
    export TTARGET="${1:?usage: ttarget <process_name>}"
    echo "target set: $TTARGET"
}

# Attach to target PID (re-run each attempt)
tpid() {
    local pid
    if [ -n "$1" ]; then
        pid="$1"
    elif [ -n "$TTARGET" ]; then
        pid="$(pidof "$TTARGET" 2>/dev/null | awk '{print $1}')"
    fi
    if [ -z "$pid" ]; then
        echo "usage: tpid [PID] or set target with: ttarget <name>"
        return 1
    fi
    echo "$pid" > $T/set_event_pid
    echo "$pid" > $T/set_ftrace_pid
    echo 1 > $T/options/event-fork
    echo 1 > $T/options/function-fork
    for tid in /proc/$pid/task/*; do
        echo "$(basename $tid)" >> $T/set_event_pid
        echo "$(basename $tid)" >> $T/set_ftrace_pid
    done
    echo "tracing pid $pid: $(cat $T/set_ftrace_pid | tr '\n' ' ')"
}

# Add ftrace filter pattern (append, use with function_graph)
# usage: trex '*vsock*'
#        trex '*virtio_transport*'
trex() {
    echo "${1:?usage: trex '<pattern>'}" >> $T/set_ftrace_filter
    echo "added: $1 (total: $(cat $T/set_ftrace_filter | wc -l) functions)"
}

# Enable function_graph tracer
tgraph() {
    echo function_graph > $T/current_tracer
    echo "${1:-20}" > $T/max_graph_depth
    if [ -n "$2" ]; then
        echo "$2" > $T/set_graph_function
    fi
}

# Add kprobe with stacktrace
tprobe() {
    echo "p:probe/$1 $1" >> $T/kprobe_events
    echo 1 > $T/events/probe/$1/enable
}

# Reset all tracing state
treset() {
    echo 0 > $T/tracing_on
    echo nop > $T/current_tracer
    echo 0 > $T/events/enable
    echo > $T/set_event_pid
    echo > $T/set_ftrace_pid
    echo > $T/set_graph_function
    echo > $T/set_ftrace_filter
    echo > $T/kprobe_events
    echo 0 > $T/options/stacktrace
    echo > $T/trace
    echo "tracing reset"
}

# Show usage examples
thelp() {
    cat <<'EOF'
ftrace helpers:

  treset                  Reset all tracing state
  tclear                  Clear trace buffer
  ton / toff              Tracing on/off
  tcat                    View trace output (trace_pipe)
  tstack / tnostack       Stacktrace on/off
  tkmem / tnokmem         kmem events on/off
  ttarget <name>          Set target process name (for tpid auto-lookup)
  tpid [PID]              Attach to PID + all threads + children (auto-resolves $TTARGET)
  trex '<pattern>'         Add ftrace filter pattern (append)
  tgraph [depth] [func]   Enable function_graph tracer
  tprobe <func>           Add kprobe for function

Setup (once):

  ttarget test

  # kmalloc/kfree with stacktrace
  treset && tkmem && tstack

  # function graph for vsock subsystem
  treset && trex '*vsock*' && trex '*virtio_transport*' && tgraph

  # kprobe on specific function
  treset && tprobe virtio_transport_destruct && tstack

Run (repeat each attempt):

  tpid && tclear && ton
  # ... trigger target in another shell ...
  toff && tcat
EOF
}
