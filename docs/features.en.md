# Penna feature guide

[Back to README](../README.en.md) · [简体中文](features.md)

## Draft and review

Results from the Agent and from Polish are submitted as pending changes. Changes are shown line by line as a red/green diff and can be accepted or rejected section by section; the draft is read-only while changes are pending. When the draft is empty, new content goes straight in.

## Sections

The draft is split into sections by labels at the start of a line, such as 【Subject】 or 【Lighting】. Each section is shown in its own colored box and can carry a line of translation (in the interface language). The **Final prompt** used for delivery strips the labels and translations automatically.

- Each section can be copied, polished, translated, pinned or deleted on its own, or taken into the chat to discuss with the Agent.
- Sections can be dragged to reorder or turned back into plain text; selected plain text can become a new section.
- Right-click a section label to rename it.
- **Merge** turns all sections on a page back into one continuous block of text.
- When the Agent changes only a few sections, it proposes changes to those sections and keeps the rest as they are.

## Pinned area

Selected text or whole sections can be pinned. The pinned area is read-only for Polish and the Agent, and can be dragged anywhere in the draft.

## Pages and series

Each page is a separate prompt, and pages can be grouped into series. There can be up to 20 series, shown five per row in up to four rows with arrows to switch rows; each series can hold any number of pages. When the series are full and the Agent needs a new one, a notice under the tabs asks you to clear some out.

- Pages in the same series share one conversation, and the Agent can refer to the other pages in the series; series are independent of each other.
- One Agent reply can write several pages at once and starts a new series automatically when the topic changes.
- Double-click a page tab or series name to rename it. Pages can be reordered or moved out of a series, and a whole series can be saved to the Archive at once.
- Right-click a series name to **Archive** it: its pages are saved to the Archive and removed from the workspace. **Manage in bulk** selects several series to archive or delete together.

## Agent chat

- Replies stream in and can be stopped or regenerated at any time; after regenerating, earlier replies can be viewed below the reply. Sent messages can be edited and resent. If a reply hits the output limit, is blocked by the API or the connection ends early, the reason appears below it.
- Messages sent while a reply is generating are queued and sent in order; a queued message can also skip the line and be sent right away.
- **Side chat**: click **Side chat** at the right end of the quick actions row to open a translucent floating panel over the conversation. It runs a separate conversation with its own model and its own Armor-Piercing switch, reads the prompts in the workspace and accepts images and text files, shares the quick actions, puts its new drafts into the workspace and switches to that page just like the main chat, and can hand layout tasks to Region Control, while the two conversations stay separate; each chat can read the other's conversation when asked. The Region Control chat has its own side chat, whose layouts go onto the canvas, and the Manga Storyboard side chat writes storyboards into the current work. A button left of **New chat** in the chat header toggles Armor-Piercing.
- Questions from the Agent appear as stacked options with single or multiple choice; when the choice is about sections of the draft, the sections of the current page are listed directly.
- When asked for tag interrogation or a specific local model, the Agent runs the model on this PC against the image in the chat; when the model is not installed yet, you choose whether to download it or use an installed one instead.
- When asked to turn the draft into JSON or lay it out by position, the Agent hands the task to the Region Control Agent. The finished layout appears in Region Control, and the JSON is also placed into a new series in the draft.
- Images (up to 10 MB) and text files can be attached with the button, by drag and drop, with Ctrl+V or Paste in the right-click menu, and are saved with the conversation; clicking an image in the chat opens it full size, where it can be copied or attached again.
- Type `@` to cite a Skill. Quick actions above the input box append to what you have typed and can be customized.
- Several conversations sit side by side as tabs; closed conversations stay in History.
- Each Preset has its own system prompt, temperature and Top P.
- Built in: "MOSS visual" (the default for new installs), "Anime" and "Photoreal". "MOSS visual" first devises the visual event happening in the picture, then the composition and camera, and writes a cohesive English description.

## Local Interrogate

Drop in, choose or paste an image from the clipboard, and a model turns it back into tags or a prompt. There are three kinds:

- **Tag Interrogate**: 20 built-in ONNX taggers in four families (WD14, PixAI, CL and OppaiOracle) produce Danbooru tags. Character and general tags each have their own threshold, and results are re-filtered instantly when it changes. Tags in the result can be toggled one by one and are all selected by default.
- **NL Interrogate**: 15 built-in vision models, covering Gemma 4 (E2B to 31B), Gemma 4 Heretic, ToriiGate, JoyCaption and Florence-2, each with a choice of quantization. GGUF models run on llama.cpp, and a running server can be added to API Management for the Agent and Polish to use. Florence-2 runs inside the app and outputs tags, captions at several levels of detail, or a composition analysis.
- **LLM Analysis**: pick one or two enabled models from API Management; they interrogate at the same time and the results are shown side by side for comparison. The writing style follows the current Preset.
- With **Compress large images** on, large images are shrunk and converted to WebP when added.
- Both kinds of models are grouped by family; families and models can be dragged to reorder.
- Models download from the official source, a HuggingFace mirror, ModelScope or a custom address; the llama.cpp runtime downloads from the official source or a GitHub mirror. When the chosen source fails, the other sources are tried in turn. Downloads are resumable and integrity-checked. Gated models use the HuggingFace token from Settings.
- **Settings → Local Interrogate** can add model folders. Folders are searched with their subfolders for existing models (compatible with the folder layouts of BooruDatasetTagManagerPlus, ComfyUI-WD14-Tagger, NLapt and the HuggingFace and ModelScope caches), and folders can also be added from the Models panel of the Local Interrogate page. The HuggingFace and ModelScope cache folders are searched automatically, and the models found are used directly. The llama.cpp runtime, run options and captioning instructions are set here as well.
- Captioning instructions can be saved like Presets: keep several, name them and switch at any time.
- Results can be copied, sent to the Agent or put into the draft.

## Region Control

Draw regions on a canvas and describe each one to produce MOSS-Image layout JSON, with a separate layout chat on the right. Shape tools above the canvas choose whether new regions are boxes, ellipses or polygons, and the pen traces any outline point by point; drag vertices to reshape. Export still writes each region as its bounding box, the Agent writes the shape into the caption, and it can draw shapes itself when laying out. The camera panel in 3D view includes a lighting assistant: 22 lighting presets, a light sphere for dragging each light's direction, with intensity, softness and color temperature, plus ambient light and atmosphere effects such as volumetric rays and haze; on export the lighting becomes a sentence appended to the overall caption, and the Agent can read and adjust it. With shading preview on, bodies and the canvas are lit and shaded by the lights. Layouts can be saved to the Region Control section of the Archive and reopen in Region Control.

- Locked art style: the Agent infers a style paragraph (including the main palette) from a reference image or description, and every layout in the same series reuses it unchanged through edits. Exported JSON prefixes the overall caption with quality tags and the style; the quality tags default to `best quality, highres, newest, year 2026, 8k resolution, masterpiece, ultra-detailed` and can be edited in the properties panel.
- Locked character cards: each character in a series has an English card (hair, eyes, hairstyle, signature items, outfit), editable in the properties panel. Exported JSON puts the card in front of every block of that character and lists the page's cast at the end of the overall caption, so features stay consistent across panels and pages.
- Regions are listed as layers (foreground, middle ground, background) and dragged to reorder; one-, two- and three-point perspective guides are available.
- The Agent receives computed spatial relations (where each region sits, which edges crop it, what overlaps what and by how much; in the 3D view, by distance from the camera, the projected outline of each volume and its visible faces) and writes them into the captions; with a reference image, it first reads the image's occlusion, cropping and camera angle before laying out regions.
- When the reference image and the canvas differ in orientation, the canvas can swap width and height to match; layouts the Agent writes at another aspect ratio are scaled proportionally into the center of the canvas.
- 3D view: every region carries a volume (distance, depth, facing) estimated by the Agent. The camera orbits, tilts, rolls, dollies and pans; boxes are recomputed for the new view, front-to-back order follows distance, and once the camera settles you are prompted to have the Agent rewrite captions for the new angle. Switching between the 2D and 3D views keeps each region's state.
- 3D navigation follows Blender: middle-drag to orbit, Shift+middle-drag to pan, Ctrl+middle-drag or the wheel to dolly; numpad 1, 3 and 7 switch to front, side and top views, and 2, 4, 6, 8 rotate step by step; Shift+` enters free camera, with WASD to move and Q/E to go down and up. The camera panel sits to the right of the canvas and collapses into a narrow strip; with a region selected, its volume's position, size, depth and facing can be set directly there.
- In the 3D view, perspective guides are computed from the camera, and dragging a vanishing point adjusts the camera (pitch and orbit, plus field of view with two-point perspective). Switching to 3D with perspective guides on first fits the camera to the guides, leaving the layout unchanged; one- and two-point perspective use lens shift so verticals stay vertical, while three-point perspective sets the camera tilt from all three vanishing points. Vanishing points can be dragged outside the frame, where they show as draggable markers on the canvas edge.
- Scene camera: in the 3D view, a second viewport opens beside the canvas while the main camera stays fixed. The viewport orbits, pans and zooms freely and shows the ground grid, every volume, and the main camera with its field of view; dragging a volume there moves it along the ground and updates the boxes on the canvas. Canvas and viewport are arranged side by side or stacked to suit the canvas aspect ratio.
- The canvas can go full screen, filling the window together with the camera panel for easier camera work and arranging; press Esc to return.
- When estimating distances, objects standing on the ground are placed by how far their bottom edge is from the horizon.
- Layers can be hidden on the canvas without affecting the exported JSON; text layers are hidden by default in the 3D view.
- Layers can be locked: a locked layer cannot be selected or dragged on the canvas, so new boxes can be drawn inside its area.
- The history lists each step — drawing, moving, turning the camera, the Agent placing a layout — and can go back to before or after any of them.

## Manga Storyboard

A page for designing manga storyboards: "Setting" and "Panel" on the left, series and their pages in the middle, the gacha bar below, and the storyboard Agent's chat on the right.

- **Series**: a series is one work with its own title, setting, characters and pages. The series are listed above the canvas, with the current one expanded into page numbers; add pages or start a new series, and right-click to rename or delete (up to 20 series). "Save" stores the whole work in the Archive's "Manga" section with the first page's mannequin image as preview, and the Archive can open it back in the Manga Storyboard.
- **Setting**: title, world and art style, and each character's name, height and looks. The Agent reads the whole setting when it writes; settings given in chat can be added to the left by the Agent.
- **Panels**: each page is a tree of cuts measured in millimeters; cuts can slant, and panels on the page margin can bleed past the paper edge. Paper is A5, B5 or A4, read right to left (manga) or left to right, with the reading order marked on each panel. Drag a gutter to resize (slanted ones keep their slant; each side at least 15 mm); a selected panel can be split top/bottom or left/right, merged with the neighbor from the same cut, set to bleed, or cleared.
- **Mannequins**: each panel shows sketch-style jointed mannequins for its cast (white bodies with thin outlines, egg-shaped heads with center and eye lines, small joint circles; female, male or neutral build), framed by shot size (full body for extreme wide and full shots, waist-up for medium, chest-up for close-up, head for extreme close-up), sized by height, panel width and head count, and facing each other when there are two. 33 built-in poses come in six groups (standing, gestures, action, sitting, kneeling and crouching, lying); actions such as hands on hips, arms crossed, waving, pointing, chin in hand, running, jumping, punching, sitting, cross-legged, kneeling, crouching or lying set the matching pose, and high and low angles change the proportions. Click a mannequin to select it, then pick a pose from the drawn thumbnails in "Panel" and set its facing, front/three-quarter/side/back view and size; drag a mannequin to put it anywhere in the panel. Name tags, speech bubbles (tails pointing to the speaker, narration in boxes) and shot labels sit alongside. "Mannequins" in the top bar switches back to text, and "Flow" connects the panels in reading order. The Agent can also assign poses when it writes the storyboard.
- **Panel**: shot size (extreme wide to extreme close-up), angle (eye level, high, low, side, from behind, over the shoulder), cast, action and scene, lines with speakers, and weight (small, normal, key); locked panels are left alone by shot draws and the Agent.
- **Gacha**: "Draw layouts" cuts a batch of layouts tier by tier in one of four styles (Dialogue, Standard, Action, Splash). "Tune" adjusts tiers, row and column slant, bleed, sub-splits, big panels and border width, sets a fixed panel count, and draws 8, 16 or 24 at a time. Candidates are scored by rules of thumb (no thin strips, varied sizes, a big key panel), show the current page's mannequins, and scroll sideways when they don't fit. Click a thumbnail to preview it on the canvas; "Use this" applies it and moves the existing content over in reading order. "Draw shots" picks shot size and angle for unlocked panels: wide at the start of a page, close on key panels, and no repeated shot size next door. The same seed and settings always draw the same results.
- **Storyboard Agent**: breaks the story into pages and panels from the setting, one beat per panel, moving from wide to close, with full dialogue; when the panel count changes, the page is re-cut by weight.
- **Generation**: "To Region Control" turns the page into a paneled layout (a box per panel, slanted panels as polygons, bleeding panels to the canvas edge; one block per character and line, with looks in the character cards) in a new Region Control series, attaches the page's mannequin reference, and asks the Region Control Agent to place characters and bubbles per the "Comic panels" Skill and write the descriptions in English, for one image of the whole page. "To Workbench" also attaches the reference and asks the Workbench Agent to write the whole page as one multi-panel manga prompt (overall style and panel layout first, then a section per panel) in a new series. The chat on the right has a side chat, and like Region Control its width changes by dragging the divider.
- Undo and redo (Ctrl+Z, Ctrl+Y); "Export PNG" saves the page at 300 DPI, with mannequins or text.

## Comics

Region Control lays out multi-panel comic pages. Following the "Comic panels" Skill, the Agent first plans the panels: a page has key panels and smaller ones, with optional slanted gutters; each panel is one block, and every character and speech bubble inside it gets a block of its own. Panels drawn by hand on the canvas are kept as drawn, and the Agent fills them in one by one. Character cards follow the series, so each character keeps the same hair, eyes, hairstyle and outfit across panels and pages.

A three-page comic laid out in Penna and rendered with MOSS-Image:

<p align="center">
  <img src="comic-1.webp" width="32%" alt="Comic page 1">
  <img src="comic-2.webp" width="32%" alt="Comic page 2">
  <img src="comic-3.webp" width="32%" alt="Comic page 3">
</p>

## Danbooru tags

- About 76,000 common tags built in, with post counts and Chinese meanings, searchable offline.
- Online semantic search can be connected to find tags from a plain description.
- The Agent looks tags up before writing them and checks the delivered draft against the dictionary afterwards; questionable tags are listed separately.

## Characters

- About 74,000 Danbooru characters built in, ordered by popularity and searchable by English name, Chinese and Japanese aliases, or series name.
- Each character's feature tags are split into **Looks** and **Outfit and other**, so the appearance or the outfit can be used on its own.
- A character search also lists the character's other forms (transformations and costumes tagged under a different name, collected from Danbooru's character wiki pages), with the feature tags of each form.
- The **All** tab searches your own characters and the built-in ones together.
- Separate **Mine**, **Built-in** and **Favorites** tabs. **Mine** holds your own characters (a name, aliases, a description, a prompt and a picture), each with any number of named outfits, and can be reordered by dragging.
- Built-in series and characters can be added to **Favorites** for quick access.
- The Agent can search the character library during a chat (by name or alias, including descriptions and outfits) and save characters to it. When a message names a character from the library, its trigger and feature tags are looked up in advance and sent to the Agent with the message.

## Polish and translate

- Polish works on a whole page, a single section or a selected piece of text, and can use its own model.
- Translation supports Google, Baidu and Alibaba machine translation, called in the order you set, with automatic retries and engine switching.
- Translating a section writes its translation line; translating selected text shows the result in a translation card.

## Skills

A Skill is a writing guide (`SKILL.md`) that decides how the Agent writes prompts.

- 10 are built in. The core ones come first and cannot be turned off; the rest are enabled by default and each can be switched on or off. The writing, scene planning and character library guides are core and always loaded; the others are listed by name and summary, and the Agent loads them when needed or when named with `@` (the always-loaded core ones are not in the `@` list); the Skills loaded for a reply are listed above it. When the picture is not yet specific, "Scene planning" first shows one questionnaire: the items to settle are listed together, each with the recommended option preselected, and are sent back in one go before the prompt is written. "Comic panels" handles multi-panel comic pages in a single image (panel layout, speech bubbles and speakers, consistency across panels) and can lay a comic page out in Region Control, with varied panel sizes and slanted gutters; panels drawn by hand on the canvas are kept as drawn and filled in one by one. "Hajimi Art Director" is an art-direction knowledge base: narrative and storyboards, composition, value structure and clean colour, design of characters, character sheets, E2 splash art, monsters and maps, and direction methods for combat, two-character stand-offs, disasters, psychological drama and dynamic close-ups. Only its table of contents is carried; the Agent loads modules one at a time when needed. Storyboards of separate images (one shot per page) are part of it.
- Import `.md` or `.zip` files, or write one directly in Settings. The `.md` / `.txt` files packed next to `SKILL.md` in a `.zip` are that Skill's modules, which the Agent loads one at a time when needed, so a large knowledge base keeps only its table of contents loaded.
- Ask the Agent in chat to write a new Skill; it is added automatically when done.

## API Management

- Supports OpenAI-compatible APIs, the Google API (including Vertex AI) and Grok account sign-in.
- Context usage: a ring next to the send button shows how much of the model's context limit the current chat uses; hover for a panel with a color-coded ring showing the share of the system preset, Skills, built-in rules, draft, chat, tool results and attachments, along with input, cache and output counts and the current API and model. Opening an earlier chat shows the estimated context to load. Limits are recognized from the model name and can also be set on the API card.
- Thinking effort: a button below the input box opens a card with a slider for Low, Medium, High and Max, each with its own color. Medium is the default, and the setting applies to chat, polishing and the side chat. If a model does not support the chosen level, Penna steps down or uses the model's default.
- Web search: the Agent can look things up online. The search runs on an API with a search tool (Gemini, Grok, OpenAI, Zhipu, Bailian, OpenRouter), selected automatically or chosen in Settings, so a model without search can still use it. During and after a search, the query and a short summary of the result appear above the reply.
- **Providers** prefills the URL and model for DeepSeek, Zhipu GLM, Kimi, Alibaba Cloud Model Studio; add the key to start.
- Name, URL, models and key take effect after clicking **Save**.
- One API can hold several models; all models form a fallback chain in order and switch automatically.
- The Agent and Polish can each have a preferred model.

## ComfyUI generation

Penna uses ComfyUI as its image generation backend, talking to ComfyUI's built-in API with no plugins.

- **Connection**: **Settings → ComfyUI** holds several ComfyUI servers (local or cloud), each with a name, address and key (sent as Bearer); the connection test shows latency. The local one defaults to `http://127.0.0.1:8188`.
- **Workflow**: until a workflow is imported, a built-in text-to-image workflow is used with the first model in ComfyUI. Several JSON files from ComfyUI's **Export (API)** can be imported and switched at any time: the prompt goes into the positive prompt box (found along the sampler's positive link, through FluxGuidance and BasicGuider); a box containing `{{prompt}}` takes precedence. The seed is randomized on every run.
- **Generate**: **Generate** on the **Final prompt** card sends the current prompt to ComfyUI; when the series has more than one page, **Series images** next to it queues every page in order from page 1, asking first above 60. The **Generate** tab next to **Draft summary** shows queueing and generation progress with large previews of this session's images, which open full size on click.
- **Side panel**: the right edge of the Workbench and Region Control has a column of icons for ComfyUI, past chats and the Piercing toggle; panels open semi-transparently over the chat. The ComfyUI panel shows connection status and latency, with dropdowns for the server and the workflow; LoRA loaders in the workflow (the core LoRA loaders, model-only, rgthree Power Lora Loader and LoRA stacks) are read, and LoRAs can be toggled, reweighted, added or removed, with changes saved to the workflow. The current LoRA combination can be saved as a preset and presets switched in one click.
- **Generate from chat**: **Settings → ComfyUI** chooses between generating right away and confirming first; when confirming, a **Generate** button appears below the reply and starts only on click. Draft cards in chat also have a **Generate** button. Ask the Agent for an image in chat or the side chat (for example "show me one"); it generates from the current page's prompt or the prompt it just wrote, with progress and images shown below that reply. When asked for a different model, the Agent switches to the workflow that uses it, and asks first when none does.
- **Image folder**: images are saved in `Documents\Penna\images` with names starting `Penna-`. The location can be changed in Settings, and existing images move with it.
- **Previews**: on saving to the Archive, the newest image generated from that prompt (or the newest image overall) becomes a WebP preview; **Save series** adds previews only to pages that have generated images.

## Archive, history and rollback

- **Archive**: drafts, Region Control layouts and manga works saved by hand, in three sections, with names and categories.
- **Image queue**: clicking **Generate** while an image is being generated adds the new job to a queue that starts as soon as the previous one finishes. The **Image queue** on the far left of the Studio lists queued, running and finished jobs with a thumbnail, time, duration and prompt; click a thumbnail to view it, regenerate finished jobs in one click, and cancel jobs that are still waiting.
- **Images**: the Archive's **Images** section reads the images in ComfyUI's output folder and fills in prompts from its generation history (including runs started in ComfyUI). For a local ComfyUI it reads the output folder on disk, subfolders included, even while ComfyUI is closed; the folder is found from ComfyUI's launch arguments or can be chosen by hand. Images can be filtered by folder, with the top level of output as its own option; grouped by date into collapsible sections and shown as a list or large thumbnails, with the time and the prompt used; click to view the original, right-click to copy the image or the prompt, put the prompt back into the draft, or delete it from ComfyUI's history (the original stays in ComfyUI's output folder).
- **Pose library**: faceless mannequin pose line art in 7 categories (standing, sitting, kneeling / squatting, lying, inverted / acrobatic, duo with mixed levels, upper body and hands), each pose drawn from angles such as front, 3/4, side, above and below. The pack is downloaded or imported as a ZIP before use, from GitHub (mirror), GitHub or ModelScope (the ModelScope edition has no NSFW content); open a pose, pick an angle and **Attach to chat** to hand the image to the Agent as a body reference, or **Copy image** to the clipboard. The series the author marks as suggestive is hidden by default. When a described scene has a clear pose or camera angle, the Agent asks whether to attach matching pose references and, once you agree, attaches a few line drawings as body references.
- **Notes**: notebooks in the sidebar for quick notes; each notebook holds multiple entries with a name and content, saved as you type.
- **Prompt history**: recorded automatically on accept, copy and clear, up to 100 entries; each can be expanded or put back into the draft.
- **Activity**: records structural operations such as pages, pins and accept/reject; the changes from one Agent reply count as one step. Any step can be revisited from before or after, back and forth; after going back, new operations start a branch and the earlier steps stay available on the other branch.

## App settings

**Settings → App settings** gathers interface language, dark mode, fonts and avatars, version and updates, and app information.

- **Language**: 简体中文, 繁體中文, English and 日本語, applied immediately. In Chinese and Japanese interfaces, section translations and machine translation use that language; the English interface shows the English text directly.
- **Dark mode**: follow the system, always on, always off, or custom hours (overnight included), with the new colors expanding in a circle.
- **Fonts and avatars**: Latin and CJK fonts can be a built-in font or any installed font; the Agent and user avatars can be replaced with your own pictures.

## Updates

Penna checks GitHub for new versions on every start, and you can also check by hand in **Settings → App settings**. When a new version is found, its release notes are shown; after you confirm, it downloads, replaces itself and restarts. The package is fetched through mirror nodes in mainland China first, switches to another node if a download breaks off, and is verified by SHA256.

## MCP

Add MCP servers over HTTP or stdio, test the connection and list their tools.

## Data files

All data is stored on this PC in `Documents\Penna` (`~/Documents/Penna` on Linux).

| Category | File | Contents |
| --- | --- | --- |
| Settings | `config.json` | Models, translation, appearance and other settings |
| Secrets | `keys.dat` / system keyring | All API keys: encrypted with Windows DPAPI into `keys.dat` on Windows, kept in the system keyring (libsecret) on Linux; only the current user on this PC can read them |
| Workspace | `workspace.json` | Drafts, conversations, prompt history |
| Archive | `archive.json` | The Archive |
| Generation | `images\` | Images generated by ComfyUI (location can be changed in Settings) |
| Manga Storyboard | `manga.json`, `manga_chat.json` | The storyboard and the storyboard Agent's chat |
| Notes | `notebooks.json` | Notebooks and their entries |
| Poses | `poses\` | The downloaded or imported pose library |
| Characters | `characters.json`, `characters\` | Saved characters and their pictures |
| Interrogate | `reverse.json`, `reverse.img` | Reference image and interrogation results |
| Local Interrogate | `local.json`, `models\`, `runtime\` | Local Interrogate settings, downloaded models and the llama.cpp runtime |
| Extensions | `skills\` | Imported Skills |
