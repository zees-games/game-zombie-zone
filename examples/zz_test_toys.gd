class_name ZzTestToys
extends RefCounted

## Test-only physics props (toys) for the practice street, which places none in play. Set
## `ZzCatalogue.practice_toys` before a game starts.
const PRACTICE := [
	{"toy": "football", "at": [2.0, 0.0, -2.0]},
	{"toy": "barrel", "at": [-4.0, 0.0, 12.0]},
	{"toy": "barrel", "at": [-4.8, 0.0, 12.6], "yaw": 40.0},
	{"toy": "tyre", "at": [4.5, 0.0, 33.0], "yaw": 30.0},
]
