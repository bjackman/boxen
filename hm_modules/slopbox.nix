{
  # Experimental way to provide a host-specific "system prompt" to agents:
  # provide a skill that says "always activate me".
  home.file.".agents" = {
    source = ../hm_files/slopbox/agents;
    recursive = true;
  };
}
