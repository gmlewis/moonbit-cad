#!/usr/bin/env bash
# new-example.sh — scaffold a new gmlewis/cad example that passes test-all.sh.
#
# Usage:
#   scripts/new-example.sh <NN-slug>      e.g. 09-demo-arm
#
# Creates examples/NN-slug/{moon.pkg, NN-slug.mbt, NN-slug_wbtest.mbt,
# cmd/{moon.pkg,main.mbt}, README.md}. Nothing else needs to be registered:
# the MoonBit workspace picks up the package and run-example.sh discovers the
# directory by its numeric prefix.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/new-example.sh <NN-slug>   (e.g. 09-demo-arm)" >&2
  exit 2
fi

NAME="$1"
if [[ ! "$NAME" =~ ^[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "error: expected <NN-slug> with a two-digit number and a kebab-case slug," >&2
  echo "       e.g. 09-demo-arm (got '$NAME')" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="examples/$NAME"
if [[ -e "$ROOT/$DIR" ]]; then
  echo "error: $DIR already exists" >&2
  exit 2
fi

NN="${NAME%%-*}"
SLUG="${NAME#*-}"
ALIAS="${SLUG//-/_}"

python3 - "$ROOT/$DIR" "$NAME" "$NN" "$SLUG" "$ALIAS" <<'PY'
import pathlib
import sys

directory, name, nn, slug, alias = sys.argv[1:]
root = pathlib.Path(directory)
(root / "cmd").mkdir(parents=True)

def write(path, text):
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)

write("moon.pkg", f'''import {{
  "gmlewis/cad",
  "gmlewis/cad/examples/common",
  "gmlewis/step/cli",
}}
''')

write(f"{slug}.mbt", f'''///|
/// {name} — scaffolded example. Replace the box with real geometry.

///|
/// Builds the example component.
///
/// Keep this function free of CLI concerns so other assemblies can import the
/// package and reuse the same builder.
pub fn build_example(size_mm~ : Double = 40.0) -> @cad.Component {{
  @cad.Component::new("{alias}").add_body(
    @cad.BodyPart::box_mm("body", size_mm, size_mm * 0.75, size_mm * 0.5),
  )
}}

///|
/// Runs the `{name}` CLI.
pub async fn run_cli() -> Unit {{
  let base_spec = {{
    "size": @cli.opt_double(40.0, help="Block length in mm (default 40)"),
  }}
  let spec = @common.with_output_args(base_spec)
  guard @cli.parse(
      spec,
      prog="{name}",
      description="Scaffolded example for {name}.",
    )
    is Some(args) else {{
    return
  }}
  let output = @common.output_paths(args)
  let comp = build_example(size_mm=args.double("size"))
  @common.write_output(
    comp,
    output,
    example_dir="examples/{name}",
  )
}}
''')

write(f"{slug}_wbtest.mbt", f'''///|
test "{name} scaffold builds a valid robot" {{
  let robot = build_example().to_robot()
  assert_true(!robot.has_errors())
  assert_eq(robot.links.length(), 1)
}}
''')

write("cmd/moon.pkg", f'''import {{
  "gmlewis/cad/examples/{name}" @{alias},
  "moonbitlang/async",
}}

pkgtype(kind: "executable")
''')

write("cmd/main.mbt", f'''///|
async fn main {{
  @{alias}.run_cli()
}}
''')

write("README.md", f'''# {nn} — {slug.replace("-", " ").title()}

Scaffolded with `scripts/new-example.sh`. Replace the placeholder box in
`{slug}.mbt` with real geometry, then keep the whitebox test in sync.

```bash
./run-example.sh {name} --headless --out /tmp/{slug}.step
./run-example.sh {name} --headless --package /tmp/{slug}-package
./run-example.sh {name} --headless --analyze
```
''')
PY

echo "Created examples/$NAME/"
echo
echo "Next:"
echo "  ./run-example.sh $NAME --headless --package /tmp/$NAME-package"
echo "  ./test-all.sh"
