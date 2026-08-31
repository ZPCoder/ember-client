# Legacy card-art mount point

The historical Flutter client expects card faces in this directory, but the
binary card-art set is intentionally absent from Git. Migration or archival QA
must hydrate the immutable asset manifest from object storage before visual
testing. This placeholder keeps Flutter's declared asset directory valid for
the retained rule-test baseline.
