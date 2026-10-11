This is a game to demonstrate the capabilities of the [**Dot collection**](https://moddingcommunity.com/co/4-dot-assets) built on-top of [Godot 4](https://godotengine.org/) and [TMC's gaming platform](https://moddingcommunity.com/play). In this 3D game, a team of up to eight survivors fights through a city at night, from one safe room to the next, against a horde that is directed rather than random and against special infected that each have one nasty trick. Zombies drop boxes that do something random when you open them, good or very bad. This is inspired by the co-operative zombie shooters and the big community servers that ran them with twenty-odd players and a hundred kinds of party box!

**This project and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This project, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## How it plays
There are two kinds of map.

- **Campaign maps** go from a start safe room to an end safe room. On the way there is usually something to do: cut a lock, raise a shutter, radio a boat. Doing it is loud, and you have to hold out while everything that heard it comes for you. Get everybody who is still standing into the end room and the map is won, and the next one in the campaign starts. Lose and you play it again, a couple of times, before the server moves on.
- **Survival maps** are a place to hold for a few minutes while the horde gets worse.

**The horde.** Commons stand about the map, sit, feed and shamble. They see you, scream, and the scream wakes everybody near them. Every minute and a half to three minutes a mob comes from somewhere you cannot see, and the director paces it: it builds up, peaks, and gives you a breather. Only six of them swing at one survivor at a time; the rest circle round. They hit for a little on normal and for a lot on expert.

**The specials.** One trick each, and they wait for a good moment to use it.

| Special | What it does |
| --- | --- |
| Leaper | Pounces from cover and pins you to the floor |
| Strangler | Grabs you with a tongue from far away and drags you to it |
| Bloater | Bursts when it dies (or when it gets close) and covers everybody near in bile, which draws the horde |
| Ram | Charges through the team, carries one of you off and pounds you into the ground |
| Spitter | Spits acid that pools on the floor and burns more the longer you stand in it |
| Rider | Jumps on your back and steers you away from your friends |
| Brute | Huge, slow to kill, throws rocks, and knocks people across the street |
| Sleeper | Sits crying in the dark. Leave her alone. If you get too close she goes for whoever woke her |

Anybody pinned needs a friend: shoot what holds them or shove it off.

**Downs.** At zero health you go down, not out: you can still shoot your pistol while you bleed out, and a friend holding **E** on you gets you up on borrowed health that drains away. Go down a third time and you are dead. Dead survivors are rescued beside the team after a while. A medkit heals most of what is missing and clears your downs; pills give borrowed health now.

**Boxes.** Zombies sometimes drop a box, and specials drop them more often. There are eight kinds and seventy-six things they can do: an airstrike on whoever is closest, a ring of fire, healing for the team, a bigger horde, a swarm of specials, a minigun, low gravity, swapping places with a friend, or a curse. Many of them last a while and stack with the same effect from another box, and the HUD lists what is running. The box file is `boxes/boxes.json` and a server owner can change or add to it.

| Box | What to expect |
| --- | --- |
| Explosive | Airstrikes, booby traps, grenades, a big gun |
| Incendiary | Fire on the zombies, or on you |
| Med | Healing, medkits, getting people up, or poison |
| Horde | More, bigger and faster mobs, or a calm |
| Special | Specials, harder specials, a brute, or a cull |
| Arsenal | Better weapons, ammo, hollow points |
| Mystery | Anything: gravity, speed, teleports, invulnerability |
| Cursed | Mostly bad, sometimes not |

**Friendly fire is on**, at a tenth of the damage on normal and much more on expert. Stand-ins fill the team up to four when there are not enough people, and they shoot, revive, heal and pick things up, and they do not shoot through you.

**Two weapon packs.** The server carries [zee-dot-weapons](https://github.com/zees-games/zee-dot-weapons) (blasters, melee weapons, grenades) and [zed-dot-weapons](https://github.com/zees-games/zed-dot-weapons) (real-world pistols, shotguns, a hunting rifle, a machine gun, launchers, a flamethrower, and the molotov, pipe bomb and bile jar) side by side, and the maps, the boxes and the stand-ins hand out weapons from both. A molotov sets the ground on fire, a pipe bomb beeps and pulls the horde to it before it goes off, a bile jar brings every zombie nearby to where it broke, and the flamethrower sets whatever it touches alight.

There are six maps: the **practice street** built into the game, the three-map **Blackout** campaign (Corner Shop, The Depot, The Pier), and two survival maps, **Parking Lot** and **Chapel Yard**, from [zombie-zone-maps](https://github.com/zees-games/zombie-zone-maps). At the end of a campaign the players vote for what is next.

## Controls

| Key | Action |
| --- | --- |
| **WASD** / mouse | Move and look |
| **Space** | Jump |
| **Ctrl** | Duck |
| **Mouse 1** / **R** | Fire / reload |
| **1**-**5** / mouse wheel | Weapons |
| **E** | Use, pick up, revive a friend (hold) |
| **F** / **Mouse 2** | Shove |
| **H** | Medkit: on yourself, or on the friend you are looking at (hold) |
| **Q** | Take pills |
| **V** | Talk (voice) |
| **F5** | First or third person |
| **Tab** | Scoreboard (hold) |
| **Esc** | Settings, including every key above |

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The game is built from many Dot addons, each in its own repository, so the easiest way to get everything is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap). It clones every project and links the addons into each one:

```bash
git clone https://github.com/modcommunity/dot-bootstrap.git
cd dot-bootstrap
./bootstrap.sh
cd projects/game-zombie-zone
./game.sh
```

On Windows, run `bootstrap.ps1` instead and open the project in Godot.

The maps come from the zombie-zone-maps checkout, which bootstrap links into `maps/` for you. On a deployed server they come from the server instead: the game ships only its built-in practice street, and the server owner picks the maps pack (`gamemann/zombie-zone-maps`, or their own) in dot-server-deploy's `cfg/content.yml`.

`game.sh` does everything else:

| Command | What it does |
| --- | --- |
| `./game.sh` | Play offline with three stand-ins |
| `./game.sh online` | Start a local server and the browser client, and print the link to open |
| `./game.sh online down` | Stop them |
| `./game.sh server` | Start a local dedicated server only |
| `./game.sh test` | Check every script and run every test suite |
| `./game.sh shot` | Save a screenshot to `screenshots/`. `tools/shot.sh` lists the views |
| `./game.sh help` | All of the options |

`online` and `server` use [dot-server-deploy](https://github.com/modcommunity/dot-server-deploy), which bootstrap clones next to this one. Run its `./setup.sh` once first.

## Running a server
Settings are cvars. Set them in the server's config, on the command line, or live from the console. Most of them take effect straight away; the ones about a map's layout take effect from the next map.

```
zz_difficulty 1                // 0 easy, 1 normal, 2 advanced, 3 expert
zz_friendly_fire 0.1           // a teammate's bullet as a share of what it does to a zombie, before difficulty
zz_max_incaps 2                // downs before the next one is death
zz_rescue_seconds 75           // seconds before a dead survivor is rescued beside the team (0 never)
zz_start_grace 60              // seconds the start room holds the horde off unless somebody leaves it
zz_survive_seconds 480         // how long a survival map is held when the map does not say
zz_map_on_loss 0               // after a lost map: 0 play it again, 1 move on
zz_retries 2                   // times a lost map is played again before moving on
zz_commons 24                  // commons alive at once for one survivor
zz_commons_per_survivor 6      // and for each survivor more
zz_wanderers 0.55              // commons standing about a map, per 100 square metres
zz_mob_min 90                  // seconds between mobs, from
zz_mob_max 180                 // seconds between mobs, to
zz_mob_size 14                 // commons in a mob, for one survivor
zz_specials 2                  // specials alive at once for one survivor
zz_special_min 18              // seconds between specials, from
zz_special_max 40              // seconds between specials, to
zz_brute_min 300               // seconds between brutes, from (0 with zz_brute_max 0: never)
zz_brute_max 480               // seconds between brutes, to
zz_director 1                  // whether the build-up, peak and relax pacing runs
zz_sleepers 1                  // whether the maps' sleepers are there
zz_box_drops 1                 // whether zombies drop boxes
zz_box_common 0.012            // chance a common drops a box
zz_box_special 0.3             // chance a special drops a box
zz_gravity 20                  // metres per second squared, for everything
bot_quota 4                    // players a round is kept at with bots; each person who joins replaces one
bot_quota_mode fill            // fill (as above), fixed (that many bots), per_player (that many per person) or off
zz_bots 1                      // 0 to turn the stand-ins off
```

The bot cvars are the family's shared ones (dot-server's `DotBotQuota`). `zz_min_players` still works and sets `bot_quota`; it is deprecated.

The second weapon pack is a config setting rather than a cvar, because a weapon rig reads its weapons once: `--zz-second-weapon-pack false` on the command line (or `second_weapon_pack` in the config file) runs the server with zee-dot-weapons alone.

```
zz_spectate_camera 0           // who somebody who is out may watch: 0 anybody, 1 their own side, 2 nobody
```

Console commands:

| Command | What it does |
| --- | --- |
| `zz_status` | What the map is doing: survivors, horde, director, objective |
| `zz_maps` | Every map, and any file that was refused and why |
| `zz_map <id>` | Play a map next, when this one ends |
| `zz_reload` | Read the map directory again (from the next map) |
| `zz_boxes` | Every box type and what it can do |
| `zz_net` | What the netcode is doing |
| `zz_say <text>` | Say something to everybody, as the server |

Admin commands, for seeing what happens (they need the `z` flag):

| Command | What it does |
| --- | --- |
| `zz_spawn <kind> [count]` | Spawn a zombie by your feet (or the team's): `common`, `leaper`, `strangler`, `bloater`, `ram`, `spitter`, `rider`, `brute`, `sleeper` |
| `zz_box [type]` | Drop a box in front of you |
| `zz_mob [size]` | Send a mob now |
| `zz_panic [seconds]` | Mobs back to back |

## Writing a map
Maps are JSON documents. The format, and how to add one, is in [zombie-zone-maps](https://github.com/zees-games/zombie-zone-maps/blob/main/maps/README.md).

## Testing
`./game.sh test` checks that every script parses and then runs every suite:

| Suite | What it checks |
| --- | --- |
| `headless_run` | The game itself: the horde noticing, chasing and hitting, shots and headshots, downs and revives, borrowed health, the shove, every special, acid and fire, loot, every box outcome, objectives and gates, winning and losing, the stand-ins, and that sixty zombies on one survivor fit in a tick |
| `headless_maps` | Every map: it fits on the wire, every prop is known, every spawn has room, items can be picked up, the zombies can reach everything that matters, and a shut gate really is shut |
| `headless_net` | A client and a server in one process: zombies, downs, pins, loot, boxes, gates and the end of a map all reach the client |
| `dedicated` | The game as a real server runs it: the module, the console, a map played by stand-ins, the map vote, and a clean exit |

`xvfb-run -a godot --path . res://tools/audio_probe.tscn` checks that the game actually makes a noise, which a headless run cannot.

## Not done yet
- **Bile that turns the horde on itself.** A bile jar draws the zombies today; the commons it splashes are not yet attacked by the others.
- **Finales with a rescue vehicle**, multi-floor maps with stairs, and more campaigns.
- **Playing it with people.** How hard normal should be, how often a mob comes and how much a box should do are numbers only play settles.

## Credits
The zombies are Kenney's Animated Characters, re-skinned. The cars, street furniture, crates, gravestones and furniture are Kenney's Car Kit, Retro Urban Kit, City Kit (Roads), Survival Kit, Graveyard Kit, Nature Kit and Furniture Kit, and the first-person arms are his Blocky Characters ([kenney.nl](https://kenney.nl), CC0). The zombie moans are from [Darsycho](https://opengameart.org/content/zombie-moans) and [ianzazz](https://opengameart.org/content/zombie-noises-and-moans) on OpenGameArt (CC0), and the specials' voices are made from them; the rest of the sounds and the music are Kenney's. `sounds/CREDITS.md` lists every file. The weapons are from [zee-dot-weapons](https://github.com/zees-games/zee-dot-weapons) and [zed-dot-weapons](https://github.com/zees-games/zed-dot-weapons) (Kenney's Blaster Kit, Weapon Pack and Food Kit, CC0). Floors, walls and roofs are his Prototype Textures under a dusty pastel; the remaining surfaces (metal, glass, water, lines) are drawn in code. Each kit's licence is next to its files.

## License
MIT. See [LICENSE](LICENSE). The Kenney art and the OpenGameArt sounds are CC0, which is public domain.
