# 生成音频的来历（2026-11-20）

全部用 image-gen MCP 生成：音效 `generate_sound_effects`（elevenlabs-sound），背景音乐 `generate_bgm`（elevenlabs-music）。
文件在 `assets/audio/sfx/*.mp3`、`assets/audio/bgm/*.mp3`（已随仓库入库）。生成服务给的下载链接是带签名的临时地址（7 天过期），不入库；
下面只留每个文件的 request_id 备查，要换某一条就拿提示词重新生成。
提示词里只写声音本身，没有带项目 / 用户信息。

| 名字 | 秒 | 提示词 |
|---|---|---|
| swing | 1 | A single fast sword swing whoosh through the air, thin steel blade, crisp and short, no impact |
| swing_heavy | 1 | A heavy powerful two-handed sword swing whoosh, deep air displacement, large blade cutting air |
| hit | 1 | A sharp sword slash hitting a body, quick punchy blade impact, tight and dry |
| hit_heavy | 1 | A heavy blade impact with deep bass thud and bone-crunching weight, powerful critical hit |
| slam | 2 | A massive ground slam impact, a heavy body crashing into stone ground with low rumble and rock debris |
| thud | 1 | A soft dull thud of feet landing on packed dirt, short low body fall |
| block | 1 | A steel sword block, blade parried with a short hard metallic clang |
| clash | 2 | Two swords clashing edge to edge with a bright resonant metallic ring and a shimmer of sparks |
| execute | 2 | A decisive finishing sword strike: deep cutting slash impact followed by a long ringing blade resonance |
| dodge | 1 | A very quick light dash whoosh with a flutter of cloth robes |
| warp | 1 | A fast magical teleport blink, bright airy zip whoosh with a faint sparkle tail |
| perfect | 2 | A bright crystalline chime with a soft reversed whoosh, perfect-timing dodge cue |
| shatter | 2 | Stone and crystal shattering into many small fragments, brittle crumbling debris |
| chip | 1 | A few small stone chips and pebbles clattering onto hard ground |
| ascend | 2 | A magical rising shimmer, spiritual energy gathering upward with bright bell tones and soft wind |
| levelup | 2 | A short triumphant level-up jingle: quick ascending guzheng pluck with bright bell chimes |
| realm_up | 4 | A grand breakthrough fanfare: deep temple gong, rising shimmering chimes, burst of radiant energy |
| skill_sword | 2 | A sharp sword energy slash unleashed, rushing wind blade with a bright metallic shing |
| sword_array | 2 | Many flying swords unsheathing at once and hovering, layered metallic shings with a rising magical hum |
| ult | 4 | A huge magical sword formation activating: deep bass swell, hundreds of blades ringing, thunderous release |
| thunder | 3 | A powerful lightning bolt striking close by with a sharp electric crack followed by rolling thunder |
| pickup | 1 | （第二版）A clear bright two-note chime, glassy bell ding with a sparkle, loud and present, short item collect sound —— 第一版「soft jade chime」出来几乎没声，弃用 |
| ui_click | 1 | A soft wooden tap, gentle short UI button click like a small woodblock |
| portal | 2 | A magical portal opening, swirling energy whoosh with a deep resonant hum and airy sparkles |
| heal | 2 | （第二版）A warm magical healing spell cast, rising shimmering bells and a soft whoosh of light, clearly audible and full —— 第一版太轻，弃用 |
| chest | 2 | Opening an old wooden treasure chest, short creak of the lid followed by a sparkle of treasure |
| horn | 3 | A deep distant ceremonial horn call, a single long blast echoing across mountains |
| boss_roar | 2 | A deep menacing roar of a huge beast, low growling monster roar |
| defeat | 3 | A somber low gong with a slow descending fading tone, defeat |
| bgm/hub | 70 | Peaceful instrumental: gentle guzheng and bamboo flute over soft pads, floating island town hub, calm, hopeful, loopable |
| bgm/explore | 80 | Adventurous exploration: flowing erhu and flute over light percussion, plucked pipa, airy, journey and wonder, loopable |
| bgm/battle | 70 | Intense battle: driving taiko drums, fast pipa and erhu riffs, brass and strings, urgent and heroic, loopable |

## request_id

| 文件 | request_id |
|---|---|
| bgm/battle.mp3 | 98509d8b-56de-4d1c-bd33-9d20a79cde89 |
| bgm/explore.mp3 | 81c2f355-faa8-449c-9b64-671c6fac42ad |
| bgm/hub.mp3 | 4d5ecc23-e4a3-41fe-a190-fa77ccfc270e |
| sfx/ascend.mp3 | d4292122-506a-44c2-bbb9-fb2569c76785 |
| sfx/block.mp3 | cfed0d53-bedd-40af-a686-2cca0dda4ed4 |
| sfx/boss_roar.mp3 | f3351d8f-6b4c-4a21-a86e-58246170cedb |
| sfx/chest.mp3 | 312e9b06-804b-4706-afe3-08c24362fae9 |
| sfx/chip.mp3 | 77c72b42-2957-4997-8c09-b7f0ff106aef |
| sfx/clash.mp3 | ea59aac7-2873-4dc6-adea-104f77b147dd |
| sfx/defeat.mp3 | a9a8a54e-9e61-4968-9e3a-467d9330aec8 |
| sfx/dodge.mp3 | dda88e03-f49b-48b6-b0ac-ce6fce81b808 |
| sfx/execute.mp3 | 19b56b16-5daf-4180-841a-262e5ea2ac47 |
| sfx/heal.mp3 | 40ba83fc-0172-412f-9e20-f5845f919bb9 |
| sfx/hit.mp3 | 91cebbb8-4f42-4dd3-ab6f-60c8097b7dcf |
| sfx/hit_heavy.mp3 | bc88f490-c958-4d33-89ad-61af624b42c7 |
| sfx/horn.mp3 | 6ee293ca-97fc-4fb2-84d0-e310e9c7cd46 |
| sfx/levelup.mp3 | 208ea3e9-05a3-44b7-8f70-8f5f6b23828b |
| sfx/perfect.mp3 | 337a13cf-42e0-47c0-9915-a1f74e4c2fd0 |
| sfx/pickup.mp3 | 82627862-9f94-4eed-9334-33da550d1a18 |
| sfx/portal.mp3 | 738dbbe7-85ed-485e-bed5-000808c14b2d |
| sfx/realm_up.mp3 | 24ed0eb0-9d24-4806-801d-e99a4df3f37f |
| sfx/shatter.mp3 | 5be44032-f199-4ffa-92ce-be53f4f17b9c |
| sfx/skill_sword.mp3 | 73e0adaa-cd0e-4fa7-af9a-1875e85808b1 |
| sfx/slam.mp3 | afb7ef3a-db3c-4b1c-893b-19d522900dab |
| sfx/swing.mp3 | 261f5f7c-ceb5-4d67-aace-4897da804e78 |
| sfx/swing_heavy.mp3 | 1765d8d0-1376-4951-bf7c-f685bef0837a |
| sfx/sword_array.mp3 | d82d2935-572d-4acb-905a-917ec8405a0b |
| sfx/thud.mp3 | e2e742d0-8528-44e0-8349-15494a3d0a04 |
| sfx/thunder.mp3 | 9a090208-7f2a-4df8-ba22-da325fd2f589 |
| sfx/ui_click.mp3 | 0bdf07ab-c499-41b2-8648-e3c7aade0807 |
| sfx/ult.mp3 | 7dc7d110-3a34-4130-840a-162c5d977115 |
| sfx/warp.mp3 | a5e10863-a5a0-4ec7-bb55-a6556091becb |
