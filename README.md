# CeolKit

A Swift package for parsing and rendering ABC music notation.

This package is inspired by [abcm2ps](https://github.com/lewdlime/abcm2ps) and created specifically to generate
sheet music for [Silicon Valley Pipe Band](https://siliconvalleypipeband.org). So, features and capabilities
have largely been driven by the needs of the pipe band musicians.

## Libraries

| Product | Purpose |
| --- | --- |
| `CeolKitModel` | The domain model — `Score`, `Tune`, `Voice`, `Measure`, `Event`. |
| `CeolKitParser` | ABC source → `Score`, with diagnostics. |
| `CeolKitRenderer` | The renderer protocol and shared rendering utilities. |
| `CeolKitSVGRenderer` | Engraves a `Score` as one SVG string per page. |
| `CeolKitSVGGeometry` | Reads emitted SVG back into layout geometry. |

## ckprobe

`ckprobe` is a development tool that parses and renders an ABC file and reports what came
out: diagnostics, tune structure, and the geometry of every system on every page. It is
not shipped as a product — run it from a checkout.

```bash
swift run ckprobe tune.abc
```

```
pages: 2
  page[0] 792 x 612, systems: 7
      #  abcLine  staffGap  x-span             width  barlines
      0        1         6  36..756              720  4
      1        1         6  36..756              720  1
```

| Option | Effect |
| --- | --- |
| `--scale <factor>` | Override `%%ceolkit:scale` before rendering. |
| `--sweep <f,f,…>` | Render at each factor; print a systems/pages table. |
| `--natural` | Force `%%ceolkit:justifylast false`, so widths are unstretched. |
| `--out <dir>` | Write `page0.svg`, `page1.svg`, … into `<dir>`. |
| `--json` | Emit JSON instead of the text report. |

`I:abc-include` resolves against the ABC file's own directory, so a file that pulls in a
shared style header behaves the way it does in a host application.

To look at a page, rasterize it — [`rsvg-convert`](https://gitlab.gnome.org/GNOME/librsvg)
handles the embedded Bravura font correctly:

```bash
swift run ckprobe tune.abc --out /tmp/out
rsvg-convert -w 1500 /tmp/out/page0.svg -o /tmp/page0.png
```
