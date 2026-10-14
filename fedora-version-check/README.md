<!-- AUTO_GENERATE_START -->
# Check Fedora Spec Version

Check that the spec `Version` matches the upstream version in `debian/changelog`,
so the Fedora and Debian packages of a repo ship the same release.
<!-- AUTO_GENERATE_END -->

## Usage

```yaml
- uses: regolith-linux-fedora/actions/fedora-version-check@fedora/main
  with:
    # name of the package. The spec is <name>.spec at the top of the repo.
    #
    # Required.
    name: "..."

    # path to the package repository.
    #
    # Optional. Defaults to "."
    path: "."
```

The upstream version is the `debian/changelog` version without its epoch and
Debian revision: `1:2.0.6-1regolith1` compares as `2.0.6`. A repo without
`debian/changelog` passes.

## Outputs

| Name | Description | Example |
|------|-------------|---------|
| `spec-version` | Version from the spec | `2.0.6` |
| `debian-version` | Upstream version from `debian/changelog` | `2.0.6` |
