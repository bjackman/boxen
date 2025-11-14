function diff_commits --argument-names commit1 commit2
    git range-diff $commit1^..$commit1 $commit2^..$commit2
end