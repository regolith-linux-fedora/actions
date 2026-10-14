<!-- AUTO_GENERATE_START -->
# Update Manifest

Update and upload the manifest file for the package that is just built with
package name, repo, ref, and sha.
<!-- AUTO_GENERATE_END -->

## Usage

```yaml
- uses: regolith-linux/actions/update-manifest@main
  env:
    # GITHUB_TOKEN is used to commit and push to Voulage.
    #
    # Required.
    GITHUB_TOKEN: ${{ env.GITHUB_TOKEN }}
  with:
    # name of the package to update the manifest for.
    #
    # Required.
    name: "..."

    # repo is the public git repository URL of the package
    #
    # Required.
    repo: "..."

    # ref is Git repository ref that the package was built at (e.g. branch, tag, or hash).
    #
    # Required.
    ref: "..."

    # sha is the commit SHA of the repository that the package was built at.
    #
    # Required.
    sha: "..."

    # matrix is encoded JSON list of target distro, codename, and architecture
    #
    # Required.
    matrix: "..."

    # suite is Regolith package archive suite (e.g. unstable, testing, stable).
    #
    # Required.
    suite: "..."

    # component is Regolith package archive component (e.g. main, v3.2, v3.1).
    #
    # Required.
    component: "..."

    # voulage-repo and voulage-ref update another voulage and branch.
    #
    # Optional. Defaults to regolith-linux/voulage at main.
    voulage-repo: ""
    voulage-ref: ""
```

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

      - name: Update Manifest
        uses: regolith-linux/actions/update-manifest@main
        env:
          GITHUB_TOKEN: ${{ env.GITHUB_TOKEN }}
        with:
          name: "foo-package"
          repo: "${{ github.server_url }}/${{ github.repository }}.git"
          ref: "${{ github.ref }}"
          sha: "${{ github.sha }}"
          matrix: "[{"distro":"ubuntu","codename":"noble","arch":"amd64"}]"
          suite: "unstable"
          component: "main"
```
