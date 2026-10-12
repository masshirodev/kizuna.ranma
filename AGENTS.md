# AGENTS.md

kizuna.ranma is a ranma plugin in Lua: `plugin/kizuna.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).
What it reads is `kizuna peers --json`, documented in kizuna's
`doc/agent-messaging.md`.

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Use only API the latest ranma release has: CI loads the plugin into it.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- Test against a private ranma server and a fake `kizuna` script first on
  `PATH`, never by sending a message to a real running agent.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
