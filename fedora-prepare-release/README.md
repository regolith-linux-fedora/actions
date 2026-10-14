<!-- AUTO_GENERATE_START -->
# Prepare Fedora Release

Read `Version` and `Release` from the package spec and derive the Fedora release
tag `fedora/v<Version>-<Release>`. Update the corresponding Fedora `testing`
package models in voulage with that tag for the provided package.
<!-- AUTO_GENERATE_END -->

## Usage

```yaml
- uses: regolith-linux-fedora/actions/fedora-prepare-release@fedora/main
  with:
    # name of the package. The spec is <name>.spec at the top of the repo.
    #
    # Required.
    name: "..."

    # repo is the public git repository URL of the package.
    #
    # Required.
    repo: "..."

    # ref is the branch the release is made from (e.g. fedora/main).
    #
    # Required.
    ref: "..."

    # voulage-repo and voulage-ref are the voulage and branch to update.
    #
    # Optional. Defaults to regolith-linux-fedora/voulage at fedora/main.
    voulage-repo: "..."
    voulage-ref: "..."
```

Run it in a checkout with tags fetched (`fetch-depth: 0`), in a `ci-fedora`
container (it needs `rpmspec`). `%{?dist}` is left out of the tag. Only models
whose unstable Fedora ref equals `ref` are updated, as in `prepare-release`.

## Outputs

| Name | Description | Example |
|------|-------------|---------|
| `release-exists` | `true` if the tag already exists, `skip` if no Fedora unstable model builds from `ref` (nothing to release), else `false` | `false` |
| `release-version` | The release tag | `fedora/v0.1.0-1` |
| `voulage-path` | The path voulage is cloned into | `/tmp/voulage-actions-repo` |
