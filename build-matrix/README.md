<!-- AUTO_GENERATE_START -->
# Build Matrix of Supported OS

Build a matrix of currently supported distros and codenames in encoded JSON list
format. The list is being built out of `stage/unstable` folder of [voulage](https://github.com/regolith-linux/voulage/).
<!-- AUTO_GENERATE_END -->

## Usage

```yaml
- uses: regolith-linux/actions/build-matrix@main
  with:
    # type of matrix to build (either for a package, or the whole CI platform)
    #
    # Required.
    type: "package"

    # name of the package to build.
    #
    # Required, if type is package
    name: "..."

    # ref is a valid git repository ref to checkout the code from (e.g. branch, tag, or hash).
    #
    # Required, if type is package
    ref: "..."

    # stage is Regolith release stage (e.g. unstable, testing, stable).
    #
    # Required.
    stage: "..."

    # arch is Regolith architectures (amd64, arm64)
    #
    # Required.
    arch: "..."

    # distro and codename only include matching targets (e.g. fedora, 43).
    #
    # Optional.
    distro: ""
    codename: ""

    # voulage-repo and voulage-ref read the stage tree from another voulage.
    #
    # Optional. Defaults to regolith-linux/voulage at main.
    voulage-repo: ""
    voulage-ref: ""
```

A distro level model (e.g. `stage/unstable/fedora/package-model.json`) is
applied between the stage and codename models, as voulage merges them.

Fedora items also carry `container`, the `ci-fedora` image to build in
(`FEDORA_CI_IMAGE` overrides the image name), and `canary`, which is `true`
for Rawhide. Canary jobs should use `continue-on-error`.

## Outputs

| Name | Description | Example |
|------|-------------|---------|
| `includes` | Encoded JSON list of matrix `include` items | <pre>[{<br>&emsp;&emsp;"distro": "ubuntu",<br>&emsp;&emsp;"codename": "noble",<br>&emsp;&emsp;"arch": "amd64"<br>}, {<br>&emsp;&emsp;"distro": "ubuntu",<br>&emsp;&emsp;"codename": "oracular",<br>&emsp;&emsp;"arch": "amd64"<br>}]</pre> |
| `runners` | Encoded JSON list of runners runs-on labels | <pre>{<br>&emsp;&emsp;"amd64":"ubuntu-24.04",<br>&emsp;&emsp;"arm64":"ubuntu-24.04-arm"<br>}</pre> |

## Scenarios

```yaml
jobs:
  matrix-builder:
    runs-on: ubuntu-24.04
    outputs:
      includes: ${{ steps.builder.outputs.includes }}
    steps:
      - name: Build Matrix
        id: builder
        uses: regolith-linux/actions/build-matrix@main
        with:
          name: "${{ github.event.repository.name }}"
          ref: "${{ github.base_ref }}"
          stage: "unstable"
          arch: "amd64 arm64"

  build:
    runs-on: ubuntu-24.04
    container: "${{ matrix.distro }}:${{ matrix.codename }}"
    needs: matrix-builder
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.matrix-builder.outputs.includes) }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build Package
        uses: regolith-linux/actions/build-package@main
        with:
          name: "foo-package"
          distro: "${{ matrix.distro }}"
          codename: "${{ matrix.codename }}"
          stage: "unstable"
          suite: "unstable"
          component: "main"
          arch: "${{ matrix.arch }}"
```

[voulage]: https://github.com/regolith-linux/voulage/
