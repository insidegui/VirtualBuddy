# VirtualCatalog

This directory includes models and associated logic used by VirtualBuddy to inspect and resolve downloadable restore images for virtual machines.

The catalog itself is a JSON file stored in the VirtualBuddy GitHub repository.

There are two JSON files for the current version of the catalog:

- `ipsws_v2.json`: for macOS virtual machines
- `linux_v2.json`: for Linux virtual machines

In order to avoid hitting GitHub too frequently and provide server-side logic, I run a small function on Cloudflare that the app talks to via HTTP.

The server fetches the appropriate JSON file from the repository based on the request path, performs any compatibility conversions depending on the client version, then returns the catalog in the response, caching it on the CDN for a short period.

## Adding New Versions of macOS

To add a new version of macOS to the catalog, use `vctool`, which is included as part of VirtualBuddy.

If you have installed VirtualBuddy in `/Applications`, then `vctool` will be available at `/Applications/VirtualBuddy.app/Contents/MacOS/vctool`.

You may symlink `vctool` to a directory in your `PATH` or just add the corresponding `VirtualBuddy.app/Contents/MacOS` directory to your `PATH` to make running the tool more convenient.

You will also need to clone the VirtualBuddy repository itself so that you can open a pull request with the updated catalog after running `vctool`.

To add a new release to the catalog, use the `vctool catalog image add` command:

```bash
USAGE: vctool catalog image add --ipsw <ipsw> --channel <channel> --name <name> --output <output> [--force]

OPTIONS:
  -i, --ipsw <ipsw>       URL to the IPSW file.
  -c, --channel <channel> ID of the release channel (devbeta or regular).
  -n, --name <name>       User-facing name for the release (ex: "macOS 15.0 Developer Beta 4").
  -o, --output <output>   Path to the software catalog JSON file that will be updated.
  -f, --force             Replace existing build if it already exists in the catalog.
  -h, --help              Show help information.
```

Assuming you have cloned the VirtualBuddy repository in `~/Developer/VirtualBuddy`, here's an example of how you could add a new image to the catalog:

```bash
vctool catalog image add \
    -i 'https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-44534/CE6C1054-99A3-4F67-A823-3EE9E6510CDE/UniversalMac_15.5_24F74_Restore.ipsw' \
    -c regular \
    -n 'macOS 15.5' \
    -o ~/Developer/VirtualBuddy/data/ipsws_v2.json
``` 

If successful, the `ipsws_v2.json` file in your clone of the VirtualBuddy repository will have the new macOS release added to it.

You may then create a new branch in your fork and submit a pull request.

Shortly after a pull request that updates the software catalog is merged, the updated catalog is picked up by the server, making any new OS releases available in the app.

## Updating Existing Versions

If an OS build that's already in the catalog needs to be updated, just use the same command but add the `--force` flag so that it doesn't complain about the version already being in the catalog. Any changes made to the title, channel, or other properties will be updated.

## ⚠️ Important Note About New Major Versions

Adding new major OS versions (ex: macOS ~16~26) requires additional work because a corresponding release group has to be added, and that requires the availability of image assets that follow a certain specification used by the app.

For that reason, adding major new OS versions is currently reserved to the maintainer of the repository (@insidegui).