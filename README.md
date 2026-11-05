# Black Dog Jump (검은 강아지 점프)

A one-button endless runner for the browser. A black puppy runs through a cozy night city;
press (or tap, or hit Space) to jump, and hold longer to jump higher. Clear the obstacles,
grab the treats for bonus points, and beat your best score. The game gets faster the longer you run.

**Play:** https://real-woong.github.io/gitut-jump-game/

## Controls
- Mouse click / screen tap / Space: jump (hold for a higher jump)
- After a game over: tap again to restart

## Built with
Godot 4.7.2 (GDScript), exported as a single-threaded web build and published to GitHub Pages
by the workflow in `.github/workflows/deploy-web.yml`.

## Run it yourself
```
godot --path .                                                          # play in the editor runtime
godot --headless --path . --export-release Web build/web/index.html     # build the web version
cd build/web && python3 -m http.server 8000                            # then open http://localhost:8000
```
The web export needs the Godot 4.7.2 export templates installed.
