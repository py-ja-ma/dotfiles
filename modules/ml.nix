{ config, lib, ... }:

# Role ml (docs/toolchain/development/README.md): llama-server as a user service on 127.0.0.1:8080 —
# the local endpoint OpenCode and other clients use. It starts only when a model is in
# place (~/models/default.gguf: a link to one of the allowlisted models in docs/toolchain/development/README.md),
# so a fresh host has nothing running. No firewall rule: it listens on loopback only.
lib.mkIf (lib.elem "ml" config.dram.roles) {
  systemd.user.services.llama-server = {
    Unit = {
      Description = "llama.cpp server on 127.0.0.1:8080 (docs/toolchain/development/README.md)";
      ConditionPathExists = "%h/models/default.gguf";
    };
    Service = {
      ExecStart = "/usr/bin/llama-server --model %h/models/default.gguf --host 127.0.0.1 --port 8080 --n-gpu-layers 99 --ctx-size 16384";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
