<!-- AUTO_GENERATE_START -->
# Build Package

Build a package for speficied distro/codename/stage triplet. It uses package
name, package repo, and package ref to checkout the code.
<!-- AUTO_GENERATE_END -->

## Usage

```yaml
- uses: regolith-linux/actions/build-package@main
  with:
    # only-build the package, if set to false don't sign nor publish the package.
    #
    # Required.
    only-build: "false"

    # name of the package to build.
    #
    # Required.
    name: "..."

    # distro is the target distro to build the package for (debian, ubuntu, fedora).
    # fedora builds with voulage's ext-rpm.sh and, unless only-build, publishes to COPR.
    #
    # Required.
    distro: "..."

    # codename is the target codename to build the package for (e.g. focal, bullseye).
    #
    # Required.
    codename: "..."

    # stage is Regolith release stage (e.g. unstable, testing, stable).
    #
    # Required.
    stage: "..."

    # suite is Regolith package archive suite (e.g. unstable, testing, stable).
    #
    # Required.
    suite: "..."

    # component is Regolith package archive component (e.g. main, v3.2, v3.1).
    #
    # Required.
    component: "..."

    # arch is Regolith architectures (amd64, arm64)
    #
    # Required.
    arch: "..."

    # gpg-email is the email ID associated with the GPG Key.
    #
    # Required.
    gpg-email: "regolith.linux@gmail.com"

    # gpg-name is the full name associated with the GPG Key.
    #
    # Required.
    gpg-name: "Regolith Linux"

    # voulage-repo and voulage-ref get the build scripts from another voulage.
    #
    # Optional. Defaults to regolith-linux/voulage at main.
    voulage-repo: ""
    voulage-ref: ""
```

## Outputs

| Name | Description | Example |
|------|-------------|---------|
| `publish-path` | The path on disk that packages are published to | `/build/publish/` |
| `buildlog-path` | The path on disk that buildlogs are saved to | `/build/buildlog/` |

## Scenarios

```yaml
jobs:
  build:
    runs-on: ubuntu-24.04
    container: "ubuntu:noble"
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build Package
        uses: regolith-linux/actions/build-package@main
        with:
          name: "foo-package"
          distro: "ubuntu"
          codename: "noble"
          stage: "unstable"
          suite: "unstable"
          component: "main"
          arch: "amd64"
```
