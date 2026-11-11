# systemd deployment

The timer installer detects the real project directory from its own location and
uses the owner of that directory as the service account. No fixed username or
home-directory path is required.

## Install

Run the application installer first as the normal, non-root project user:

```bash
./install.sh
```

Then install the systemd templates:

```bash
sudo bash scripts/install-timers.sh
```

The installer validates the virtual environment and `.env`, renders the
service template using the detected project owner and absolute path, installs
all units, reloads systemd, and runs `systemd-analyze verify`. It does not
enable any timers automatically.

## Enable timers

The instance format is `SYMBOL-TIMEFRAME`. Keep the symbol in the format
accepted by Twelve Data and replace the slash with an underscore for a
systemd-safe instance name:

```bash
sudo systemctl enable --now market-advisor-1h@BTC_USD.timer
sudo systemctl enable --now market-advisor-4h@BTC_USD.timer
sudo systemctl enable --now market-advisor-1day@BTC_USD.timer
sudo systemctl enable --now market-advisor-1week@BTC_USD.timer
```

The template service separates the final timeframe suffix from the symbol,
converts underscores in the symbol back to slashes, and calls
`core/fetcher.py` with explicit `--symbol` and `--timeframe` arguments.

## Inspect

```bash
systemctl list-timers 'market-advisor-*'
systemctl status market-advisor-1h@BTC_USD.timer
journalctl -u market-advisor-fetch@BTC_USD-1h.service
```

Data is stored beneath the project's `data/` directory, for example
`data/BTC_USD.db`.

## Notes

- The service runs as the user who owns the checked-out project directory.
- Keep the repository, `.venv`, `.env`, `data/`, and `logs/` owned by
  that same unprivileged user.
- The service is a oneshot task; systemd starts a new fetch on each timer tick.
- If you move the project, rerun `sudo bash scripts/install-timers.sh` to
  regenerate the service with the new absolute path.
