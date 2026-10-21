# tmog

Wraps the official Task Manager TMOG Linux tarball in a pacman package and installs it, so `sudo pacman -R tmog` removes it cleanly.

```bash
./setup.sh [version]   # default: newest release on tmog.org
```

The built `.pkg.tar.zst` is saved next to the script (git-ignored). Set
`TMOG_PKG_DIR` to keep it somewhere else.
