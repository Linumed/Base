"""Rewrites `docs/img/...` image paths for the MkDocs build (issue #65).

`ARCHITECTURE.md` and `CHANGELOG.md` live in the repository root - deliberately, so that
GitHub and Forgejo render them at the paths people expect - and are pulled into the site
through symlinks (`docs/architecture.md`, `docs/changelog.md`). That makes one file
readable at two different depths, and a relative image path cannot be correct for both:

    viewed as /ARCHITECTURE.md      ->  docs/img/foo.svg
    built from docs/architecture.md ->  img/foo.svg

The sources are written for the repository-root form, because that is what GitHub and
Forgejo resolve without help. This hook strips the leading `docs/` during the site build
so MkDocs resolves the same reference against `docs/img/` instead - and, because MkDocs
then knows the file is inside `docs_dir`, it also rewrites it to the correct relative URL
for whatever page URL the page ends up at.

Registered via `hooks:` in mkdocs.yml (MkDocs >= 1.4, no plugin dependency). Without it
`mkdocs build --strict` fails on the missing image, which is the intended behaviour: a
silent fallback would let a broken diagram ship.
"""

import re

# Only image references, and only ones that start exactly at `docs/img/`. Deliberately
# narrow: a blanket `docs/` rewrite would also mangle prose that legitimately mentions a
# path under docs/, and this repo's documentation does that in several places.
_IMAGE_REF = re.compile(r"(!\[[^\]]*\]\()docs/img/")


def on_page_markdown(markdown, page, config, files):
    return _IMAGE_REF.sub(r"\1img/", markdown)
