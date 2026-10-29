# Hardware-Erkennung: liefert die passenden Treiber-Pakete für den aktuellen Rechner

hw_arch() { uname -m; }

# GenuineIntel / AuthenticAMD / leer (z.B. ARM)
hw_cpu_vendor() {
    awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || true
}

# Gibt nvidia / amd / intel / virtual (je Zeile) für jede gefundene Grafikkarte aus
hw_gpu_vendors() {
    local dev class vendor
    for dev in /sys/bus/pci/devices/*; do
        [[ -r $dev/class ]] || continue
        class=$(<"$dev/class")
        [[ $class == 0x03* ]] || continue
        vendor=$(<"$dev/vendor")
        case $vendor in
            0x10de) echo nvidia ;;
            0x1002) echo amd ;;
            0x8086) echo intel ;;
            *)      echo virtual ;;
        esac
    done | sort -u
}

# none / kvm / qemu / oracle / vmware / microsoft / ...
hw_virt() {
    local virt
    virt=$(systemd-detect-virt --vm 2>/dev/null) || true
    echo "${virt:-none}"
}

hw_has_gpu() { grep -qx "$1" <<<"$(hw_gpu_vendors)"; }

hw_has_bluetooth() { compgen -G '/sys/class/bluetooth/*' >/dev/null; }

hw_has_battery() { compgen -G '/sys/class/power_supply/BAT*' >/dev/null; }

hw_summary() {
    local gpus
    gpus=$(hw_gpu_vendors | paste -sd, -)
    info "Architektur:  $(hw_arch)"
    info "CPU:          $(hw_cpu_vendor || true)"
    info "Grafik:       ${gpus:-keine PCI-GPU erkannt}"
    info "Virtualisiert: $(hw_virt)"
    info "Bluetooth:    $(hw_has_bluetooth && echo ja || echo nein)"
    info "Akku:         $(hw_has_battery && echo ja || echo nein)"
}

# Pakete, die zur erkannten Hardware passen
hw_packages() {
    local arch gpu_count
    arch=$(hw_arch)
    gpu_count=$(grep -cv virtual <<<"$(hw_gpu_vendors)" || true)

    case $(hw_cpu_vendor) in
        GenuineIntel) echo intel-ucode ;;
        AuthenticAMD) echo amd-ucode ;;
    esac

    if (( gpu_count > 0 )); then
        echo mesa
    fi
    if hw_has_gpu intel; then
        printf '%s\n' vulkan-intel intel-media-driver libva-intel-driver
    fi
    if hw_has_gpu amd; then
        printf '%s\n' vulkan-radeon xf86-video-amdgpu
    fi
    if hw_has_gpu nvidia; then
        # nvidia-open benötigt eine GPU ab Turing (RTX 20xx / GTX 16xx).
        # Für ältere Karten in config/hardware-packages.txt bzw. manuell anpassen.
        printf '%s\n' nvidia-open-dkms nvidia-utils linux-headers egl-wayland
        if [[ $arch == x86_64 ]]; then
            echo lib32-nvidia-utils
        fi
        if (( gpu_count > 1 )); then
            echo nvidia-prime
        fi
    fi

    case $(hw_virt) in
        kvm|qemu)  printf '%s\n' qemu-guest-agent spice-vdagent mesa ;;
        oracle)    printf '%s\n' virtualbox-guest-utils mesa ;;
        vmware)    printf '%s\n' open-vm-tools mesa ;;
    esac

    if hw_has_bluetooth; then
        printf '%s\n' bluez bluez-utils
    fi
    return 0
}

# Dienste, die zur erkannten Hardware gehören
hw_services() {
    if hw_has_bluetooth; then
        echo bluetooth.service
    fi
    if hw_has_gpu nvidia; then
        printf '%s\n' nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
    fi
    case $(hw_virt) in
        kvm|qemu) echo qemu-guest-agent.service ;;
        oracle)   echo vboxservice.service ;;
        vmware)   echo vmtoolsd.service ;;
    esac
    return 0
}

# Passende ML4W-Umgebungsvariante für ~/.config/hypr/conf/environment.lua
hw_ml4w_environment() {
    case $(hw_virt) in
        none|"") ;;
        *) echo kvm.lua; return ;;
    esac
    # Nur bei reiner Nvidia-Grafik; bei Hybrid-Laptops (Intel/AMD + Nvidia) rendert die iGPU
    if hw_has_gpu nvidia && ! hw_has_gpu intel && ! hw_has_gpu amd; then
        echo nvidia.lua
    else
        echo default.lua
    fi
}
