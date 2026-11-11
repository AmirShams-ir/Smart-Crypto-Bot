# Smart Crypto Bot — Common Modules

Reusable system and application provisioning scripts shared by Market Ecosystem projects.

## Provisioning layers

1. `bootstrap.sh` — base Debian/Ubuntu server preparation.
2. `python.sh` — Python runtime, build headers and isolated virtual environment.
3. `freqtrade.sh` — clone/update and install Freqtrade into its own virtual environment.
4. `hyperopt.sh` — install and verify Freqtrade's optional Hyperopt dependencies.

## Supported base systems

- Debian 12 / 13
- Ubuntu 22.04 / 24.04

Freqtrade currently requires Python 3.11 or newer. The Python installer selects the newest installed interpreter in the supported range (3.11+), or accepts an explicit minor version through `--python`.

## Typical installation

Run base provisioning once as root:

```bash
sudo bash bootstrap.sh
```

Install the trading environment as the normal project user:

```bash
bash python.sh --system
bash freqtrade.sh
```

Install Hyperopt only on machines intended for optimization:

```bash
bash hyperopt.sh
```

Or install Freqtrade and Hyperopt together:

```bash
bash freqtrade.sh --with-hyperopt
```

## Paths and configuration

Default checkout: `common-modules/freqtrade/`

Default virtual environment: `common-modules/freqtrade/.venv/`

Override paths without editing scripts:

```bash
FREQTRADE_DIR=/opt/market-trader/freqtrade bash freqtrade.sh
FREQTRADE_DIR=/opt/market-trader/freqtrade bash hyperopt.sh
```

To request a specific installed interpreter:

```bash
PYTHON_VERSION=3.12 bash freqtrade.sh
```

The Freqtrade script uses the upstream repository's `setup.sh -i` installer and does not install into the system Python. It only operates on the `stable` or `develop` branch, rejects an existing checkout on another branch, and uses fast-forward-only updates.

## Important notes

- The optional Hyperopt requirements are intentionally separate from the live trading runtime because they are heavier and not needed to run the bot.
- TA-Lib is handled using the helper shipped with the selected Freqtrade checkout when available. Use `--no-ta-lib` only when you intentionally do not need it.
- The `--system` option in `python.sh` installs OS-level development packages and therefore requires sudo. It does not create a venv owned by root unless the script itself is run as root.
- Do not run the application installer with sudo. Run project-level installers as the normal bot user.
- These scripts install software and dependencies only. They do not generate exchange API keys, trading configuration, strategies, systemd services, or enable live trading.

## Commands

```bash
bash python.sh --help
bash freqtrade.sh --help
bash hyperopt.sh --help
```
