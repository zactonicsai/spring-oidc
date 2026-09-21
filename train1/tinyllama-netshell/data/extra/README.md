# data/extra/

Drop any number of `.jsonl` files here. `python scripts/build_dataset.py` merges them with
`../train_small.jsonl` into `../train.jsonl` and `../train_chatml.jsonl`.

One card per line:

{"instruction": "Show the routes for IPv6", "input": "", "output": "#!/bin/bash\nip -6 route show"}

Blank lines and lines starting with # are ignored. See ../../docs/04_adding_more_data.md.
