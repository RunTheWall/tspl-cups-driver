# Arch packaging

`PKGBUILD` and `.SRCINFO` here are the same files the AUR would serve. Arch
users can build straight from the repo without the AUR:

```bash
( cd packaging/aur && makepkg -si )
```

## Do not hand-edit the metadata

`pkgver`, `sha256sums` and the whole of `.SRCINFO` are derived from one input,
the released tarball:

```bash
sh packaging/aur/refresh.sh 1.3.5        # rewrites both files in place
```

Editing one without the others is what breaks AUR installs: a checksum
mismatch, or stale metadata that quietly installs the wrong version. The `aur`
job in `.github/workflows/release.yml` runs `refresh.sh` in an
`archlinux:base-devel` container, builds the package with `makepkg`, runs the
test suite through `check()`, and diffs the result against the copies here, so
drift fails CI rather than reaching a user.

## Publishing to the AUR

Not published yet. The name `tspl-cups-driver` is unclaimed.

When it is, the first push is manual and creates the package:

```bash
git clone ssh://aur@aur.archlinux.org/tspl-cups-driver.git aur-pkg
sh packaging/aur/refresh.sh <version> aur-pkg
cd aur-pkg && git add PKGBUILD .SRCINFO && git commit -m 'Initial import' && git push
```

After that it belongs in the release workflow, gated on a tag and on the
signing key being present, so a release can never ship without the AUR copy
following it. An AUR account and an SSH key registered to it are required;
the private half belongs in repository secrets, never in the tree.
