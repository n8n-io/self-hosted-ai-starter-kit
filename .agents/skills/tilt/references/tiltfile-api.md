# Tiltfile API in use

The calls the [Tiltfile](../../../../Tiltfile) makes and what each is there for. Signatures and semantics live in the [Tiltfile API reference](https://docs.tilt.dev/api.html) (Context7 library id `/websites/tilt_dev`): look a call up there before changing how it is used.

| Call | Used for |
| --- | --- |
| `version_settings(constraint='>=0.37.7')` | the minimum Tilt version; the other tool minimums live in the CLI (`REQUIREMENTS`) |
| `docker_prune_settings(...)` | Tilt's docker pruner |
| `load('ext://dotenv', 'dotenv')`, `dotenv(fn='./.env', verbose=True, showValues=True)` | exports the root `.env` into the Tilt process, so every compose project inherits `DOMAIN`. It prints the values, which is why the root `.env` never holds a secret |
| `include('ext://cancel')` | the `cancel` extension of tilt-extensions |
| `load('ext://uibutton', 'cmd_button')`, `cmd_button(name, resource, argv, icon_name, text)` | the `secrets` button of a resource: a click runs `secrets read <directory>` and prints into the log of that resource |
| `local(cmd, quiet=True, echo_off=True)` | runs the CLI (`tilt resources`, `verify --json`) and `tilt get` / `tilt enable`; returns stdout as a blob and raises on a non-zero exit |
| `decode_json(blob)` | reads the plan and the verify report |
| `encode_yaml(dict)` | turns the inline override of a project into a compose blob |
| `watch_file(path)` | re-executes the Tiltfile when the root `.env`, `models.json`, a per-service `.env` or a cascade parent changes |
| `warn(msg)`, `fail(msg)` | the warnings of the verify report, and the one error that lists its errors and hints |
| `os.path.exists(path)` | the check that the CLI bundle is built |
| `config.clear_enabled_resources()`, `config.set_enabled_resources(names)` | exactly the `enabled` resources of the plan run |
| `config.tilt_subcommand` | the enabled set is re-applied through the API server only during `tilt up` |
| `docker_compose(configPaths, project_name, profiles)` | one call per project; `configPaths` is the list of files plus the `encode_yaml()` blob of the override |
| `dc_resource(name, project_name, new_name, labels, resource_deps, links, infer_links, auto_init)` | one call per resource; the keyword names are the keys of a plan resource |

`local_resource` is not used: the Tiltfile runs commands only while it loads.

Tilt CLI commands the repository relies on (`tilt <command> --help`):

- `tilt up`, `tilt down`: only through `pnpm run dev`, which the user runs.
- `tilt alpha tiltfile-result -v`: evaluates the Tiltfile without an API server. Exit 0 when it evaluated, 5 on a Tiltfile error; the result JSON (about 30 KB) goes to stdout, the logs to stderr.
- `tilt get uiresources -o name`: the resources of the running session; without one it fails with `No tilt apiserver found`.
- `tilt enable --only <resources>`: enables those and disables every other resource.
- `tilt trigger <resource>`, `tilt logs [resource]`: against a session that already runs on port 10350.

Guides: [Docker Compose](https://docs.tilt.dev/docker_compose.html), [Tiltfile config](https://docs.tilt.dev/tiltfile_config.html), [extensions](https://docs.tilt.dev/extensions.html), [buttons](https://docs.tilt.dev/buttons.html).
