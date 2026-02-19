# Dependencies for the deploy-tf script.
{ agenix, ... }:
{
  imports = [
    agenix.homeManagerModules.default
  ];

  age.secrets = {
    arr-api-key.file = ../secrets/arr-api-key.age;
    transmission-password.file = ../secrets/transmission-password.age;
  };
}
