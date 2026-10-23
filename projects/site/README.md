# The language's site

`zap run projects/site/main.zapx`, from the repository's root, writes `projects/site/out/`: a page
that sends the browser to its language, the English and Portuguese pages, one style.css, the logo,
the projects' pictures and the charts as SVG for the README, from the components of `components/`
and the text of `content/`. The numbers come from `baselines/numbers.json` every time, never
copied (`readme/` writes the README's blocks from them). With `--publish <clone dir>`, `out/` is
then mirrored into that clone of the site's repository and committed there; the push stays by
hand. The site generator is `projects/webgen`.
