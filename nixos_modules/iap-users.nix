{
  config.bjackman.iap.users = [
    {
      name = "brendan";
      admin = true;
    }
    "ben"
    "alex"
  ];
  # You also need to add new users to the Authelia user file by running this
  # from the secrets/ dir:
  # agenix -e authelia/users.yaml.age
}
