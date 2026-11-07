#!/bin/sh

LC_ALL=C
export LC_ALL

section() {
    printf '\n=== %s ===\n' "$1"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

show_version_if_available() {
    label=$1
    shift
    if has_command "$1"; then
        printf "%s: " "$label"
        "$@" 2>&1 | sed -n '1p'
    fi
}

show_selected_tool_version() {
    label=$1
    tool=$2
    shift 2
    tool_path=
    if [ -n "$developer_dir" ] && [ -d "$developer_dir" ] && has_command xcrun; then
        tool_path=$(xcrun --find "$tool" 2>/dev/null)
    fi
    if [ -n "$tool_path" ] && [ -x "$tool_path" ]; then
        printf "%s: " "$label"
        "$tool_path" "$@" 2>&1 | sed -n '1p'
    else
        printf "%s: not available in selected Xcode/Command Line Tools\n" "$label"
    fi
}

developer_dir=${DEVELOPER_DIR:-}
if [ -z "$developer_dir" ] && has_command xcode-select; then
    developer_dir=$(xcode-select -print-path 2>/dev/null)
fi

section "Host / OS"
printf "Date: %s\n" "$(date)"
printf "Hostname: %s\n" "$(hostname)"
if has_command sw_vers; then
    sw_vers
else
    printf "sw_vers: unavailable\n"
fi
printf "Kernel: "
uname -a

section "Uptime / load"
if has_command uptime; then
    uptime 2>&1
else
    printf "uptime: unavailable\n"
fi

section "Xcode / Developer tools"
if [ -n "$developer_dir" ] && [ -d "$developer_dir" ] && has_command xcrun; then
    xcodebuild_path=$(xcrun --find xcodebuild 2>/dev/null)
    if [ -n "$xcodebuild_path" ] && [ -x "$xcodebuild_path" ]; then
        "$xcodebuild_path" -version 2>&1
    else
        printf "Xcode: not available in the selected developer directory\n"
    fi
    printf "Developer directory: %s\n" "$developer_dir"
else
    printf "Xcode/Command Line Tools: no active developer directory selected\n"
fi

if [ -n "$developer_dir" ] && [ -d "$developer_dir" ] && has_command xcrun; then
    clang_path=$(xcrun --find clang 2>/dev/null)
else
    clang_path=
fi
if [ -n "$clang_path" ] && [ -x "$clang_path" ]; then
    printf "C compiler (Clang):\n"
    "$clang_path" --version 2>&1 | sed -n '1,3p'
else
    printf "C compiler (Clang): not available in selected Xcode/Command Line Tools\n"
fi
show_selected_tool_version "cc" cc --version
show_selected_tool_version "gcc" gcc --version

llvm_path=$(command -v llvm-config 2>/dev/null)
if [ -z "$llvm_path" ] && [ -n "$developer_dir" ] && [ -d "$developer_dir" ] && has_command xcrun; then
    llvm_path=$(xcrun --find llvm-config 2>/dev/null)
fi
if [ -n "$llvm_path" ] && [ -x "$llvm_path" ]; then
    show_version_if_available "LLVM" "$llvm_path" --version
else
    llvm_path=$(command -v llc 2>/dev/null)
    if [ -z "$llvm_path" ] && [ -n "$developer_dir" ] && [ -d "$developer_dir" ] && has_command xcrun; then
        llvm_path=$(xcrun --find llc 2>/dev/null)
    fi
    if [ -n "$llvm_path" ] && [ -x "$llvm_path" ]; then
        show_version_if_available "LLVM" "$llvm_path" --version
    else
        printf "LLVM: no standalone version tool found; Clang may include its LLVM build in the version above\n"
    fi
fi

python_found=0
for tool in python python2 python3; do
    if has_command "$tool"; then
        show_version_if_available "Python ($tool)" "$tool" --version
        python_found=1
    fi
done
if [ "$python_found" -eq 0 ]; then
    printf "Python: not found in PATH\n"
fi

java_home=
if [ -x /usr/libexec/java_home ]; then
    java_home=$(/usr/libexec/java_home 2>/dev/null)
fi
if [ -z "$java_home" ] && [ -x /System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home/bin/java ]; then
    java_home=/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home
fi
if [ -n "$java_home" ] && [ -x "$java_home/bin/java" ]; then
    printf "Java: "
    "$java_home/bin/java" -version 2>&1 | sed -n '1p'
    if [ -x "$java_home/bin/javac" ]; then
        printf "javac: "
        "$java_home/bin/javac" -version 2>&1 | sed -n '1p'
    fi
else
    printf "Java/JDK: not found (no runtime launched)\n"
fi

show_version_if_available "Ruby" ruby --version
show_version_if_available "Perl" perl -e 'print "Perl $^V\n"'
show_version_if_available "Node.js" node --version
show_version_if_available "Swift" swift --version
show_version_if_available "Go" go version
show_version_if_available "Rust" rustc --version
show_selected_tool_version "Git" git --version
show_version_if_available "CMake" cmake --version
show_version_if_available "Homebrew" brew --version

section "CPU"
if has_command sysctl; then
    for key in hw.ncpu hw.physicalcpu hw.logicalcpu; do
        value=$(sysctl -n "$key" 2>/dev/null)
        if [ -n "$value" ]; then
            printf "%s: %s\n" "$key" "$value"
        fi
    done
    cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    if [ -n "$cpu_model" ]; then
        printf "Model: %s\n" "$cpu_model"
    fi
else
    printf "sysctl: unavailable\n"
fi

section "Memory"
if has_command sysctl; then
    mem_bytes=$(sysctl -n hw.memsize 2>/dev/null)
    case "$mem_bytes" in
        ''|*[!0-9]*) printf "Physical RAM: unavailable\n" ;;
        *) awk -v bytes="$mem_bytes" 'BEGIN { printf "Physical RAM: %.1f GiB (%s bytes)\n", bytes / 1073741824, bytes }' ;;
    esac
else
    printf "sysctl: unavailable\n"
fi
if has_command vm_stat; then
    vm_stat | awk '
        function emit_page(label, count) {
            if (count == "") return
            if (page_size > 0)
                printf "  %-14s %s pages (%.2f GiB)\n", label, count, (count + 0) * page_size / 1073741824
            else
                printf "  %-14s %s pages\n", label, count
        }
        function emit_counter(label, count, note) {
            if (count != "") printf "  %s: %s (%s)\n", label, count, note
        }
        /page size of/ {
            header = $0
            sub(/^.*page size of /, "", header)
            sub(/ bytes.*$/, "", header)
            page_size = header + 0
            next
        }
        /:/ {
            label = $0
            sub(/:.*/, "", label)
            gsub(/"/, "", label)
            value = $NF
            gsub(/[^0-9]/, "", value)
            if (value == "") next
            if (label == "Pages free") free_pages = value
            else if (label == "Pages active") active_pages = value
            else if (label == "Pages inactive") inactive_pages = value
            else if (label == "Pages speculative") speculative_pages = value
            else if (label == "Pages wired down") wired_pages = value
            else if (label == "Pages purgeable") purgeable_pages = value
            else if (label == "Pages occupied by compressor") compressed_pages = value
            else if (label == "Translation faults") translation_faults = value
            else if (label == "Pages copy-on-write") copy_on_write = value
            else if (label == "Pageins") pageins = value
            else if (label == "Pageouts") pageouts = value
            else if (label == "Swapins") swapins = value
            else if (label == "Swapouts") swapouts = value
        }
        END {
            if (page_size > 0) printf "Page size: %.0f bytes\n", page_size
            else print "Page size: not reported"
            print "Current page categories:"
            emit_page("Free", free_pages)
            emit_page("Active", active_pages)
            emit_page("Inactive", inactive_pages)
            emit_page("Speculative", speculative_pages)
            emit_page("Wired", wired_pages)
            emit_page("Purgeable", purgeable_pages)
            emit_page("Compressed", compressed_pages)
            print "Cumulative VM counters (since boot):"
            emit_counter("Translation faults", translation_faults, "vm_fault calls, not errors or necessarily disk reads")
            emit_counter("Copy-on-write", copy_on_write, "pages copied to preserve shared memory")
            emit_counter("Pageins", pageins, "pager requests, not necessarily swap")
            emit_counter("Pageouts", pageouts, "pages paged out")
            emit_counter("Swapins", swapins, "pages read from swap")
            emit_counter("Swapouts", swapouts, "pages written to swap")
            print "Free/inactive/speculative/purgeable pages are generally reclaimable; wired pages cannot be paged out."
            print "VM counters are lifetime totals; rates and memory pressure matter more than a single total."
        }
    '
else
    printf "vm_stat: unavailable\n"
fi

section "Memory / swap"
if has_command sysctl; then
    swap_info=$(sysctl vm.swapusage 2>&1)
    swap_status=$?
    if [ "$swap_status" -eq 0 ]; then
        printf "%s\n" "$swap_info"
    else
        printf "Swap usage unavailable: %s\n" "$swap_info"
    fi
else
    printf "sysctl: unavailable\n"
fi
printf "The direct memory-pressure graph is not sampled; use Activity Monitor. Swap and VM counters above are indicators. No pressure test is run.\n"

section "Battery"
if has_command pmset; then
    pmset -g batt 2>&1
else
    printf "pmset: unavailable\n"
fi
if has_command system_profiler; then
    printf "Battery health / capacity:\n"
    battery_details=$(system_profiler SPPowerDataType | awk '
        /Charge Remaining|Full Charge Capacity|Fully Charged|Charging|State of Charge|Cycle Count|Condition|Maximum Capacity/ {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (!seen[line]++) print "  " line
        }
    ')
    if [ -n "$battery_details" ]; then
        printf "%s\n" "$battery_details"
    else
        printf "  No battery-specific health fields reported.\n"
    fi
else
    printf "system_profiler: unavailable\n"
fi

section "Disks / Filesystem usage"
if has_command diskutil; then
    diskutil list
    root_info=$(diskutil info / 2>&1)
    root_info_status=$?
    if [ "$root_info_status" -eq 0 ]; then
        printf "\nStartup volume / disk health:\n"
        printf "%s\n" "$root_info" | awk '
            /^[[:space:]]*(Device Identifier|Part of Whole|File System Personality|Protocol|SMART Status|Disk Size|Volume Free Space|Solid State|Internal):/ {
                print
                if ($0 ~ /^[[:space:]]*SMART Status:/) smart_reported = 1
            }
            END {
                if (!smart_reported) print "SMART Status: not reported for startup volume"
            }
        '
        root_device=$(printf "%s\n" "$root_info" | awk -F: '/^[[:space:]]*Device Identifier:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }')
        root_fs=$(printf "%s\n" "$root_info" | awk -F: '/^[[:space:]]*File System Personality:/ { sub(/^[[:space:]]*/, "", $2); print $2; exit }')
        if printf "%s\n" "$root_fs" | grep -i -q 'APFS'; then
            printf "\nAPFS container capacity:\n"
            diskutil apfs list 2>&1
            if [ -n "$root_device" ]; then
                printf "\nAPFS snapshots on startup volume (%s):\n" "$root_device"
                diskutil apfs listSnapshots "$root_device" 2>&1
            fi
        else
            printf "\nAPFS container / snapshot check skipped (startup filesystem: %s).\n" "${root_fs:-unknown}"
        fi
    else
        printf "Startup volume details unavailable: %s\n" "$root_info"
    fi
else
    printf "diskutil: unavailable\n"
fi
printf "\nMounted filesystem usage (df -h):\n"
df -h

section "Network interfaces / IP addresses"
if has_command ifconfig; then
    ifconfig -a | awk '
        /^[^[:space:]]/ {
            iface = $1
            sub(/:.*/, "", iface)
            print iface ":"
        }
        /^[[:space:]]*inet[[:space:]]/ { print "  IPv4: " $2 }
        /^[[:space:]]*inet6[[:space:]]/ { print "  IPv6: " $2 }
        /^[[:space:]]*status:/ { print "  Status: " $2 }
    '
else
    printf "ifconfig: unavailable\n"
fi

section "Routing / DNS"
if has_command route; then
    route_info=$(route -n get default 2>&1)
    route_status=$?
    if [ "$route_status" -eq 0 ]; then
        route_summary=$(printf "%s\n" "$route_info" | awk '/destination:|gateway:|interface:/ { print }')
        if [ -n "$route_summary" ]; then
            printf "IPv4 default route:\n%s\n" "$route_summary"
        else
            printf "Default-route details not reported:\n%s\n" "$route_info"
        fi
    else
        printf "Default route unavailable: %s\n" "$route_info"
    fi
else
    printf "route: unavailable\n"
fi
if has_command scutil; then
    dns_info=$(scutil --dns 2>&1)
    dns_status=$?
    if [ "$dns_status" -eq 0 ]; then
        dns_summary=$(printf "%s\n" "$dns_info" | awk '
            /resolver #/ || /nameserver\[/ || /search domain\[/ {
                line = $0
                sub(/^[[:space:]]*/, "", line)
                if (!seen[line]++) print line
            }
        ')
        if [ -n "$dns_summary" ]; then
            printf "DNS resolvers:\n%s\n" "$dns_summary"
        else
            printf "No DNS resolver details reported.\n"
        fi
    else
        printf "DNS details unavailable: %s\n" "$dns_info"
    fi
else
    printf "scutil: unavailable\n"
fi

section "Security posture"
if has_command fdesetup; then
    fdesetup status 2>&1
elif has_command diskutil; then
    corestorage_info=$(diskutil cs list 2>&1)
    corestorage_status=$?
    printf "FileVault: fdesetup unavailable; using legacy CoreStorage fallback.\n"
    if [ "$corestorage_status" -eq 0 ]; then
        corestorage_summary=$(printf "%s\n" "$corestorage_info" | awk '/No CoreStorage logical volume groups found|Logical Volume Group|Encryption|Conversion/ { print }')
        if [ -n "$corestorage_summary" ]; then
            printf "CoreStorage details (not conclusive for legacy FileVault home encryption):\n%s\n" "$corestorage_summary"
        else
            printf "CoreStorage details not reported; FileVault status is undetermined.\n"
        fi
    else
        printf "CoreStorage fallback unavailable: %s\n" "$corestorage_info"
    fi
else
    printf "FileVault status: unavailable (no supported status tool)\n"
fi
firewall_tool=/usr/libexec/ApplicationFirewall/socketfilterfw
if [ -x "$firewall_tool" ]; then
    "$firewall_tool" --getglobalstate 2>&1
else
    printf "Firewall status: socketfilterfw unavailable\n"
fi
if has_command spctl; then
    printf "System policy assessment (Gatekeeper on supported macOS):\n"
    spctl --status 2>&1
else
    printf "System policy assessment: spctl unavailable\n"
fi
if has_command csrutil; then
    csrutil status 2>&1
else
    printf "System Integrity Protection: not available on this macOS release\n"
fi

section "Open ports / sockets"
if has_command lsof; then
    printf "TCP listeners:\n"
    lsof -nP -iTCP -sTCP:LISTEN 2>&1
    printf "\nUDP sockets:\n"
    lsof -nP -iUDP 2>&1
else
    printf "lsof: unavailable\n"
fi

section "Top 10 processes by CPU"
if has_command ps; then
    printf "%7s %7s %7s %7s %10s %s\n" "PID" "PPID" "CPU%" "MEM%" "RSS(KB)" "COMMAND"
    ps -A -o pid,ppid,%cpu,%mem,rss,comm | sed '1d' | sort -nr -k 3,3 | head -n 10
else
    printf "ps: unavailable\n"
fi

section "Top 10 processes by resident memory"
if has_command ps; then
    printf "%7s %7s %7s %7s %10s %s\n" "PID" "PPID" "CPU%" "MEM%" "RSS(KB)" "COMMAND"
    ps -A -o pid,ppid,%cpu,%mem,rss,comm | sed '1d' | sort -nr -k 5,5 | head -n 10
else
    printf "ps: unavailable\n"
fi

if [ "$(id -u)" -ne 0 ]; then
    printf "\nNote: some process and socket details may require running this script with sudo.\n"
fi
