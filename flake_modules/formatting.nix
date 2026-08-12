{
  perSystem = { ... }: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
      programs.mdformat = {
        enable = true;
        # Without this plugin mdformat mangles the YAML frontmatter in agent
        # Skill SKILL.md files (turns `---` into a thematic break and collapses
        # the name/description onto one line).
        plugins = ps: [ ps.mdformat-frontmatter ];
      };
      programs.yamlfmt.enable = true;
      # The flake check is really annoying as it causes deploy-rs to
      # fail, so checking the formatting is handled via a custom
      # mechanism.
      flakeCheck = false;
    };
  };
}
