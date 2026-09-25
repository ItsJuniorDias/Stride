# Image generator

Makes images for Stride with [OpenRouter](https://openrouter.ai) and Google's **Nano Banana** (Gemini 2.5 Flash Image).

1. Get an API key at openrouter.ai/keys and either export it or put it in `Tools/imagegen/.env`:

   ```
   OPENROUTER_API_KEY=sk-or-...
   ```

   `.env` is ignored by git.

2. Run from the repository root:

   ```bash
   python3 Tools/imagegen/generate.py --list                         # what's in the catalog
   python3 Tools/imagegen/generate.py empty-friends --variants 3     # three options
   python3 Tools/imagegen/generate.py --all                          # everything
   python3 Tools/imagegen/generate.py plan-10k --reference Design/Images/plan-first-5k.png
   python3 Tools/imagegen/generate.py empty-friends --install        # also into Assets.xcassets
   python3 Tools/imagegen/generate.py --name hero --aspect 16:9 --prompt "A runner at dusk"
   ```

Images go to `Design/Images/`, each with a `.json` next to it recording the prompt and model. `--install` adds the first variant (or the one `--pick N` names) to `Stride/Stride/Assets.xcassets` as an image set named in camelCase (`empty-friends` → `emptyFriends`), ready for `Image("emptyFriends")`.

`assets.json` holds the shared style (the design system's palette, no text in images) and one entry per image: name, aspect ratio, where it's used, and the prompt. Add entries there to grow the set; an entry with `"style": false` skips the shared style and carries its own (the orange app icon does, since the shared style asks for an off-white background). `--model` switches models, e.g. `google/gemini-3.1-flash-image` (Nano Banana 2) or `google/gemini-3-pro-image` (Nano Banana Pro). `--dry-run` shows the prompts without calling the API.
