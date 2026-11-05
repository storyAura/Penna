# P站大透视张力、人物特写与第一人称好感大厅CG导演系统 SKILL 0.2

本技能是面向 P 站（Pixiv）日榜/周榜高赞插画、二次元抽卡手游付费皮肤 KV、角色魅力大特写（Close-Up）以及《碧蓝档案》Memorial Lobby（好感大厅）级**第一人称 POV 互动、广角大透视张力与人物局部微演出**的视觉导演总控系统。

**核心工程哲学：不教画风，只授“叙事先行 $\rightarrow$ 客观比例尺锚定 $\rightarrow$ 素描黑白灰疏密隔离 $\rightarrow$ 透视与局部解剖特写”的主美级导演知识。** 本技能严禁输出任何改变用户固定二次元画风的画师名、手游名、渲染引擎词或真人摄影词。

---
## 壹、 六大绝对工程铁律 (Six Absolute Engineering Iron Laws)

### 1. 【铁律一：$100\%$ 零画风污染与“纯光学/解剖参数转译”防火墙】
* **绝对禁令**：严禁写入任何画师名、手游名（如 `Blue Archive, NIKKE`）、3D渲染词（`raytraced, octane render, photorealistic`）或复古年代滤镜词。
* **转译规范**：一切画面张力 $100\%$ 拆解为**物理焦段、机位距离、人体骨点比例、黑白灰明度百分比與织物挤压几何**。`Slot 6` $100\%$ 留给用户的固定画风尾缀。

### 2. 【铁律二：客观人体与道具 $1:1$ 比例尺绝对锚定律 (Objective Anthropometric & Prop Scale Law)】 ★ v0.2 核心修复
* **实测翻车病因诊断**：
  1. **道具巨型化/微缩化幻觉**（如图 `00052` 中冰淇淋甜筒画得跟少女上半身一样大，图 `00048` 中手掌与玻璃杯比例失调）：当提示词强调某个互动道具（如甜筒、茶杯、烟斗、猫、武器）但未给定**“相对于人手/人脸的客观尺寸锚点”**时，AI 会按词频权重把道具吹成气球！
  2. **人物与载具/背景巨物比例崩坏**（如图 `00050` 少女坐在空中机械巨物上像巨人，图 `00051` 坐在长椅上略偏小）：缺乏人高与座位/栏杆高度的 $1:1$ 物理咬合基准。
* **三大客观比例尺强制校准公式**：
  1. **手-脸解剖基准尺（Hand-to-Face Anthropometric Gauge）**：在所有半身与特写镜头中，强制声明 **`objective anatomical proportions: open palm length strictly equal to the character's chin-to-brow facial height, slender fingers proportionally scaled`**（手掌长度严格等于下巴至眉骨高度，严禁巨手或婴儿小手）。
  2. **手持道具 $1:1$ 真实参照锁（1:1 Real-World Prop Scale Lock）**：凡涉及手持或贴身道具（饮品、食物、烟斗、手机、信件、书本、小动物），**必须以“巴掌大小（palm-sized）”、“嘴唇宽度（lip-scaled）”或“小于面部面积 $1/3$”作为硬性物理参照**：
     * ❌ 错误写法（导致图 `00052` 巨型甜筒）：`holding a delicious strawberry ice cream cone near a cat`
     * ✅ 正确写法（锁死 $1:1$ 真实比例）：`holding a standard 1:1 palm-sized strawberry ice cream cone (the paper cone fits neatly inside her single closed hand, total ice cream height smaller than her head) while crouching beside a realistic house-cat whose shoulder height reaches only her shin`
  3. **人-座具/载具 $1:1$ 人体工学咬合尺（Ergonomic Furniture/Vehicle Scale）**：角色坐立时，小腿长度必须等于标准椅面高度（$45\text{cm}$），桌面齐腰/胸口；若骑乘或立于巨型机械/建筑上，必须通过**标准宽度护栏、扶梯踏步或铆钉尺寸**锚定人类的真实大小。

### 3. 【铁律三：素描黑白灰三带分离与“主体精刻 vs. 背景概括”疏密铁律】 ★ v0.2 核心修复
* **实测翻车病因诊断**：
  * 在图 `00039`（窗前白发OL）与图 `00048/00049`（粉色咖啡厅女仆）中，背景塞满了高饱和度、高对比度的霓虹灯牌与繁复蕾丝窗帘，且明度与角色头发完全粘连（违反 `01` 构图库与 `02` 素描库），导致画面杂乱、空间变平、眼睛找不到休息区！
* **素描与疏密三大强制铁律**：
  1. **角色头部后方强制开辟【Halo 低纹理净空区】**：在角色头部、发丝外轮廓与核心肩膀背后 $20\%$ 的区域内，**强制清空一切文字灯牌、细碎蕾丝、复杂窗格与高纯度杂物**，必须使用**连贯的深色阴影墙面、柔和的单色逆光雾团、或干净的天空/帘幕大色块**进行“亮衬暗”或“暗衬亮”托举！
  2. **双人/过肩镜头的前景暗部压制（Foreground OTS Suppression —— 修复图 `00048/00049`）**：当画面近景出现倾听者背影或 POV 角色的手臂时（如图 `00048` 左侧黑发少女、图 `00039` 左下角双手），**前景人物/手臂必须被强制归入 $15\%–25\%$ 的低饱和统一暗部阵营并施加适度光学失焦（`darkened low-contrast foreground repoussoir with soft bokeh`）**，严禁前景配角与中景主角抢夺明度对比和细节锐度！
  3. **80/20 细节疏密衰减律（80/20 Detail Density Decay）**：全图 $80\%$ 的精细结构线与高光卡点必须锁死在**中景主角的五官、发丝交界处与互动手部（最密区）**；背景建筑与桌面次要杂物强制压缩对比度、降低纯度并简化为概括的平涂大块面（最疏呼吸区）。

### 4. 【铁律四：大透视“Z轴三平面连接桥”防断肢铁律 (3-Plane Foreshortening Bridge Lock)】
* **`Plane 1 [近景突刺端]`**（手掌/足尖/刀尖） $\rightarrow$ **`Plane 2 [中景透视压缩圆柱体桥]`**（必须显式写出 `steeply foreshortened cylindrical forearm/calf receding in depth with elliptical cross-contour cuffs`，严禁手脚直接长在躯干上） $\rightarrow$ **`Plane 3 [面部核心锐利对焦层]`**。

### 5. 【铁律五：第一人称 POV 五档机位距离与特写裁切标尺】
* **`Dist_0 [0.15m 极限微距特写 ECU]`**：$100\text{mm}–135\text{mm}$ 微距镜头，仅框取**眉眼、双唇、耳垂后颈、十指交扣、绝对领域袜口或足弓**。
* **`Dist_1 [0.3m 贴脸胸像近景 CU]`**：$85\text{mm}$ 肖像镜头，裁切在**锁骨或胸口以上**，聚焦面部微表情、眼神光与手部抚脸动作。
* **`Dist_2 [0.6m 隔桌半身互动 MCU]`**：$35\text{mm}–50\text{mm}$ 镜头，裁切在**腰部或桌面以上**，表现伏案托腮、递物、共饮。
* **`Dist_3 [1.2m 沙发/床畔七分身 MS]`**：$24\text{mm}–28\text{mm}$ 广角，裁切在**小腿或包含完整坐姿全身**，表现软体家具重力下陷与交叠双腿。
* **`Dist_4 [2.0m+ 广角张力全身/大场景 WS]`**：$14\text{mm}–24\text{mm}$ 广角，表现虫视仰拍、高空俯拍或宏大灾变现场的戏剧对比。

### 6. 【铁律六：软体家具重力陷落与人体软组织挤压力学】
* 凡坐、卧、趴、靠、翘腿、捏脸，必须编译出客观的**受力凹陷折痕（`weight-bearing indentation folds`）**与**软组织挤压形变（`plush flesh compression flattening against the contact surface`）**。

---
## 第 2 阶：六大底座全联动 · 六段式黄金权重编译规范 (v0.2 Master Compiler)

每次输出 Prompt 时，Agent **必须严格按以下嵌合了【叙事层 + 客观比例尺锁 + 素描三带与 Halo 净空 + 60-30-10 防脏】的六段式结构拼接**：

```text
[Slot 1: 叙事时间切片与情绪光谱 (第1顺位) + 镜头焦段与机位距离 (Dist_0~4) + M01-M34 构图骨架]
[Narrative & Camera Master]: Captured during a moment of [填入 T01-T03 时间切片与 E01-E06 情绪氛围描述] using a [135mm macro / 85mm portrait / 28mm wide-angle / 14mm ultra-wide] lens at an interaction distance of [0.15m ECU / 0.3m CU / 0.6m MCU / 1.2m MS], structured as [填入 M01-M34 具体的特写裁切或 POV 构图英文描述]. Asymmetrical 7:2:1 mass hierarchy.

+ [Slot 2: 角色微演出焦点 + 客观人体与道具 1:1 比例尺锁 (修复巨型道具/巨人幻觉) + Z轴防断肢桥]
[Subject & 1:1 Objective Scale Lock]: Locked in razor-sharp focus is [角色外貌/八维发型/四层穿衣或局部解剖细节], [填入具体的眼神、唇齿、手指或身体微演出动作]. Strict objective anthropometric and prop scale calibration: open palm length matches facial chin-to-brow height; [若含手持道具/动物/座椅，强制填入 1:1 比例锚点：her handheld prop is rendered at true-to-life 1:1 scale fitting neatly within her palm (smaller than half her face) / seated ergonomically on a standard 1:1 scale bench/platform with human-scale railings]. [若含伸手/伸腿大透视，强制填入：Connected seamlessly by a steeply foreshortened cylindrical forearm/calf with elliptical cross-contour cuffs].

+ [Slot 3: 01构图与02素描铁律 —— 头部后方 Halo 净空保护圈 + 前中后三层灰度带 + 软体挤压/丝袜物理]
[Sketch Value Matrix & Halo Sanctuary]: Unambiguous three-band grayscale tonal separation: [若有前景遮挡物或倾听者：the foreground element is suppressed into a 15%-value darkened, low-detail repoussoir silhouette with soft bokeh]; directly behind the main character's head and hair silhouette is an unobstructed, low-texture [warm window-light shaft / unified dark wall shadow / calm twilight sky] Halo Sanctuary Zone with zero competing neon signs or cluttered patterns. Physical contact mechanics: [填入重力下陷褶皱、脸颊/大腿软肉挤压变形，或挂载《丝袜质感 SKILL 0.2》的丹尼尔数菲涅尔透肉与 1.5mm 勒肉凹陷词块].

+ [Slot 4: 80/20 距离细节疏密衰减律 + 2D 手绘背景环境概括]
[Density Rhythm & Environment]: Masterful 80/20 detail density decay: 80% of crisp structural linework and specular highlights are concentrated strictly on the character's eyes, lips, hands, and focal accessories, while the surrounding 2D hand-painted anime background environment ([具体场景名称]) is rendered with compressed tonal contrast, broad flat planes, and soft lost edges in the shadows so it recedes cleanly.

+ [Slot 5: 02明暗二分 (Notan) + 03色彩防脏处方 (60-30-10 配比与交界线暖色卡边)]
[Color & Lighting Anti-Muddy Script]: Strict two-value light and shadow grouping (Notan) with restrained bounce light in the shadows, a vibrant saturated warm color accent along the shadow terminator, and clean luminous cool-shifted shadows. Disciplined 60-30-10 color script: 60% cohesive low-saturation atmospheric base tone, 30% character local garment color, punctuated solely by a 10% high-saturation spotlight locked onto [唯一戏眼：her irises / lips / focal prop].

+ [Slot 6: 用户专属固定画风槽位 (100% 零画风污染)]
[粘贴用户固定的二次元画风尾缀或 LoRA 触发词；默认纯净底座：Modern 2D commercial gacha game illustration, delicate color-tinted structural line art, crisp 2-tone semi-thick cel shading with deep ambient occlusion accents, balanced dynamic range without blown-out highlights, masterpiece, best quality.]
```

---

> 母题库在 `T-POV-母题`,要挑母题时再加载。
