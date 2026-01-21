if status is-interactive
    alias prodmake 'make -s -j100 LLVM=1 CC="ccache clang" KBUILD_BUILD_TIMESTAMP='

    alias konjurer=/google/bin/releases/kernel-tools/konjurer/konjurer_cli
    alias crash=/google/data/ro/projects/kdump/crash
    alias kperf=/google/bin/releases/kernel-racktest/tests/kperf/kperf
    alias pastebin=/google/src/head/depot/eng/tools/pastebin
    alias copybara=/google/bin/releases/copybara/public/copybara/copybara
    alias gbuild2_remote.sh=/google/src/head/depot/google3/experimental/users/jackmanb/prodkernel_hacks/gbuild2_remote.sh
    alias kperf_kernel_ab.sh=/google/src/head/depot/google3/experimental/users/jackmanb/prodkernel_hacks/kperf_kernel_ab.sh
    alias test_asi.sh=/google/src/head/depot/google3/experimental/users/jackmanb/prodkernel_hacks/test_asi.sh
    alias approve_clean_backport.sh=/google/src/head/depot/google3/prodkernel/kvm/tools/approve_clean_backports.sh
    alias approve-clean-backport=/google/src/head/depot/google3/prodkernel/tools/review/approve-clean-backport
    alias remove_attention.sh=/google/src/files/head/depot/google3/experimental/users/jackmanb/prodkernel_hacks/remove_attention.sh

    function pull_rebase_11xx
        if not git merge-base --is-ancestor staging/mm/next HEAD
            echo "staging/mm/next not an ancestor of HEAD. Aborting."
            return 1
        end

        git checkout staging/mm/next
        and git pull
        and git checkout -
        and git rebase --update-refs staging/mm/next
    end

    abbr --add smn --position anywhere "staging/mm/next"
    abbr --add ma6 --position anywhere "mm/asi/6.6"
    abbr --add 6sm --position anywhere "6.12/staging/mm"
    abbr --add grn "git rebase --interactive staging/mm/next"
    # See set_devrez_machines.fish
    abbr --add sm 'ssh root@$MACHINE'

    function cp_upstream --argument-names commit
        set --local upstream_version (git tag --sort version:refname --contains $commit | egrep -m1 '^v[0-9]+\.[0-9]+$')
        kdt cherry-pick --upstream $upstream_version $commit
    end

    function kdt_setup
        argparse 'asi' -- $argv
        or return

        if set -q _flag_asi
            set -gx KDT_EFFORT "mm/asi"
            set -gx KDT_GOOGLE_FEATURE_DOC "ntation/google/mm/asi/asi.txtpb"
            set -gx KDT_UPSTREAM_PLAN "298091561"
            echo "ASI defaults applied: KDT_EFFORT, KDT_GOOGLE_FEATURE_DOC, KDT_UPSTREAM_PLAN."
        else
            read -P "Enter KDT_EFFORT (effort-group): " effort
            set -gx KDT_EFFORT "$effort"

            read -P "Enter KDT_GOOGLE_FEATURE_DOC (feature-doc-link): " feat_doc
            set -gx KDT_GOOGLE_FEATURE_DOC "$feat_doc"

            read -P "Enter KDT_UPSTREAM_PLAN (upstream-plan-details): " upstream
            set -gx KDT_UPSTREAM_PLAN "$upstream"
        end

        read -P "Enter KDT_GOOGLE_BUG_ID (buganizer-id): " bug_id
        set -gx KDT_GOOGLE_BUG_ID "$bug_id"

        read -P "Enter KDT_TESTED (tested-explanation): " tested
        set -gx KDT_TESTED "$tested"

        read -P "Enter KDT_FIXES (commit-ish): " fixes
        set -gx KDT_FIXES "$fixes"
    end
end
