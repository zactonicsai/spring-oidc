# plugins/

Drop your own resource plugins here (`<name>.sh`, see `scripts/resources/_template.sh`).
They are discovered automatically by `podkit resources`; a file named after a built-in
resource (for example `tls.sh`) replaces that built-in. Other locations: any directory on
`$PODKIT_PLUGIN_PATH` (colon separated) and `~/.podkit/plugins/`.
