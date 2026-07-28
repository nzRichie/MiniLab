# MiniLabs

Small network-security labs that run on one machine. Each lab spawns a handful of
containers on an isolated Open vSwitch fabric, and you play it twice: first as the
attacker, then as the defender against the same topology.

Every lab ships a handout with the graded questions you answer in a separate
document.

## Requirements

Docker, and an account in the `docker` group. That is the whole list.

You do not need root or `sudo` to run a lab. Creating the virtual links between
lab containers needs privileges your account will not have, so each lab does that
work inside a short-lived privileged container that it removes when the lab is up.

```bash
# Ubuntu
sudo apt install docker.io
sudo usermod -aG docker "$USER"   # log out and back in

# Arch
sudo pacman -S docker
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # log out and back in
```

Check it worked with `docker info`. If that prints a daemon summary rather than a
permission error, you are ready.

## Running a lab

```bash
./minilabs
```

Pick a lab to open its actions:

- **Spawn** creates the lab's containers and wires them together. The first spawn
  of a lab also pulls the upstream switch image and builds that lab's host image,
  which takes a few minutes; every spawn after that is seconds.
- **Status** prints the lab's addressing and its success oracle, so you can read
  the before/after without shelling in.
- **Shell command for a node** asks which node and prints the `docker exec -it`
  line to paste into your own terminal.
- **Reset to baseline** undoes the attack and your defences without tearing down.
- **Teardown** removes the lab. Run it when you finish.
- **Open handout** opens that lab's handout PDF.

`Back` (or Esc) returns to the lab list.

The engine streams each script's output into a panel and turns it green on
success, red on failure.

## What is here

```
minilabs            launcher: elevates and starts the menu
minimanager         the TUI engine (static binary, no runtime dependencies)
config.toml         the lab menu
labs/<lab>/         one directory per lab
  manifest.toml       the lab's metadata and addressing
  handout.pdf         the follow-along guide and its graded questions
  scripts/            the lifecycle scripts the menu runs
  default_config/     each device's starting configuration
  image/              the Dockerfile for the lab's container image
```

## Safety

Every lab runs on an isolated bridge with no route off the host, and each lab's
scripts only touch containers that lab created. Teardown removes that lab's
containers and nothing else.
