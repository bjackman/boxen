if status is-interactive
    function g4d
        cd (p4 g4d $argv)
    end

    # sudo glinux-add-repo fish-google
    # sudo apt update
    # sudo apt install fish-google-config
    source_google_fish_package citc_prompt

    alias kbug='/google/bin/releases/kernel-security-team/kbug'
    alias msv='/google/bin/releases/msv-sre/clis/msv'
    alias update_fresh.sh='/google/src/files/head/depot/google3/java/com/google/devtools/fresh/tools/update-fresh/update_fresh.sh'
    alias gemini='/google/bin/releases/gemini-cli/tools/gemini'
    alias netboot-ovss='/google/bin/releases/platforms-ovss/netboot-ovss'
end
