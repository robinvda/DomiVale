"""Growth simulation of the DomiVale rules as written in DESIGN.md.

The defaults are the rules as the design states them; the figures in DESIGN.md
section 13 come from running this with no flags. Greedy bots play 20 rounds on
boards scaled to the house count, and the report shows growth pace, crowns by
banner, crowns by seat and the late-game value of a Monument against a Siege.

    python3 tools/growth_sim.py [seeds] [flags]

seeds is the number of four-house boards (default 40); two- and three-house
runs use half as many. Flags switch to the variants section 13 and section 15
discuss, so a rejected rule can be re-measured:

    --step=N            basic price rises every N districts (default 3)
    --reach1            Monument scores own plain cells within reach 1
    --settle-banner     the Expander's banner card is a Settle
    --banner-round=N    banner cards enter the hand at the start of round N
    --found2            a founded heart claims reach 2 instead of 3
    --settle-pile       Settle is always buyable at its rising price
    --settle-rise=N     that price rises by N of each good per extra city

Modelled: scaled boards, reach-3 claiming, basic districts with the rising
price, 3 plays a turn, hand cap, bank trading, the rotating first seat, the
opening hand (Farm, a chosen basic, the banner card), Monument crowns, renown,
start-of-turn reachability for city cells, abandonment of cut-off districts.

Not modelled: the market row and deck (no card buys besides basics, so no
Settles, Walls, Barracks or Markets), height, heart capture, fallen land.
Only a Warlord ever attacks, with its one Siege.
"""
import random
import statistics as st
import sys
from collections import defaultdict

MEADOW, FOREST, HILLS, WATER = 0, 1, 2, 3
GOODS = ("grain", "wood", "stone")
KIND_TERRAIN = {"farm": MEADOW, "lumber": FOREST, "quarry": HILLS}
TERRAIN_GOOD = {MEADOW: "grain", FOREST: "wood", HILLS: "stone"}
ROUNDS = 20
BOARD_FOR = {2: 22, 3: 27, 4: 32}
PLAYS = 3
HAND_CAP = 5
SIEGE_STRENGTH = 4
FOUND_REACH = 3      # reach a newly founded heart claims
MONUMENT_MODE = 'touching'  # 'touching' or 'reach1'
PRICE_STEP = 3       # basic price rises by 1/1 every PRICE_STEP districts
BANNER_ROUND = 1     # round at whose start the banner card enters the hand
SETTLE_PILE = False  # Settle always buyable from a pile at settle_price
SETTLE_RISE = 1      # +SETTLE_RISE of each good per city beyond the first
EXPANDER_BASIC = True  # Expander's banner card is an extra basic; False gives it a Settle


def reach_offsets(r):
    return [(dx, dy) for dx in range(-r, r + 1) for dy in range(-r, r + 1)
            if dx * dx + dy * dy <= (r + 0.5) ** 2]


R3 = reach_offsets(3)
R1 = reach_offsets(1)
R2 = reach_offsets(2)
ORTHO = [(1, 0), (-1, 0), (0, 1), (0, -1)]
FOUND_OFFSETS = {3: R3, 2: R2}


def value_noise(n, rng, scale):
    g = scale + 2
    grid = [[rng.random() for _ in range(g)] for _ in range(g)]
    out = [[0.0] * n for _ in range(n)]
    for y in range(n):
        fy = y / n * scale
        iy = int(fy)
        ty = fy - iy
        sy = ty * ty * (3 - 2 * ty)
        for x in range(n):
            fx = x / n * scale
            ix = int(fx)
            tx = fx - ix
            sx = tx * tx * (3 - 2 * tx)
            a, b = grid[iy][ix], grid[iy][ix + 1]
            c, d = grid[iy + 1][ix], grid[iy + 1][ix + 1]
            out[y][x] = (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy
    return out


def make_board(n, rng):
    e = value_noise(n, rng, max(3, n // 6))
    m = value_noise(n, rng, max(3, n // 5))
    t = [[MEADOW] * n for _ in range(n)]
    for y in range(n):
        for x in range(n):
            if e[y][x] < 0.24:
                t[y][x] = WATER
            elif e[y][x] > 0.70:
                t[y][x] = HILLS
            elif m[y][x] > 0.58:
                t[y][x] = FOREST
    return t


def start_positions(n, houses):
    i = 4
    if houses == 4:
        return [(i, i), (n - 1 - i, n - 1 - i), (n - 1 - i, i), (i, n - 1 - i)]
    if houses == 2:
        return [(i, n // 2), (n - 1 - i, n // 2)]
    return [(n // 2, i), (i, n - 1 - i), (n - 1 - i, n - 1 - i)]


class City:
    def __init__(self, heart):
        self.heart = heart
        self.districts = {}  # pos -> kind


class House:
    def __init__(self, hid, banner):
        self.id = hid
        self.banner = banner
        self.goods = {"grain": 2, "wood": 2, "stone": 1}
        self.hand = []
        self.cities = []
        self.renown = 0
        self.income_last = 0
        self.siege_round = None


class Game:
    def __init__(self, seed, banners):
        self.rng = random.Random(seed)
        self.nh = len(banners)
        self.n = BOARD_FOR[self.nh]
        n = self.n
        while True:
            self.terrain = make_board(n, self.rng)
            starts = start_positions(n, self.nh)
            if all(self.terrain[y][x] != WATER for x, y in starts):
                # fairness: each start has at least 6 meadow, 4 forest, 4 hills in reach 3
                ok = True
                for sx, sy in starts:
                    cnt = defaultdict(int)
                    for dx, dy in R3:
                        x, y = sx + dx, sy + dy
                        if 0 <= x < n and 0 <= y < n:
                            cnt[self.terrain[y][x]] += 1
                    if cnt[MEADOW] < 6 or cnt[FOREST] < 4 or cnt[HILLS] < 4:
                        ok = False
                if ok:
                    break
        self.owner = [[-1] * n for _ in range(n)]
        self.cell = [[None] * n for _ in range(n)]  # (house, city, kind)
        self.houses = [House(i, b) for i, b in enumerate(banners)]
        self.round = 0
        self.stats = []
        self.late_options = []  # (round, best_monument, best_siege or None)
        for h, (x, y) in zip(self.houses, starts):
            self.found_city(h, (x, y))
        for h in self.houses:
            self.opening_hand(h)

    # --- geometry -------------------------------------------------------
    def inb(self, x, y):
        return 0 <= x < self.n and 0 <= y < self.n

    def land(self, x, y):
        return self.terrain[y][x] != WATER

    def claim(self, h, pos, offsets=R3):
        px, py = pos
        for dx, dy in offsets:
            x, y = px + dx, py + dy
            if self.inb(x, y) and self.land(x, y) and self.owner[y][x] == -1:
                self.owner[y][x] = h.id

    def claim_count(self, pos, offsets=R3):
        px, py = pos
        c = 0
        for dx, dy in offsets:
            x, y = px + dx, py + dy
            if self.inb(x, y) and self.land(x, y) and self.owner[y][x] == -1:
                c += 1
        return c

    def plain_own(self, h, x, y):
        return self.inb(x, y) and self.owner[y][x] == h.id and self.cell[y][x] is None

    def yield_at(self, h, pos, kind):
        t = KIND_TERRAIN[kind]
        px, py = pos
        return sum(1 for dx, dy in ORTHO
                   if self.plain_own(h, px + dx, py + dy) and self.terrain[py + dy][px + dx] == t)

    def monument_crowns(self, h, pos):
        px, py = pos
        offs = ORTHO if MONUMENT_MODE == 'touching' else R1
        return sum(1 for dx, dy in offs if (dx or dy) and self.plain_own(h, px + dx, py + dy))

    def own_monuments_near(self, h, pos):
        px, py = pos
        c = 0
        for dx, dy in R1:
            x, y = px + dx, py + dy
            if self.inb(x, y):
                cc = self.cell[y][x]
                if cc and cc[0] == h.id and cc[2] == "monument":
                    c += 1
        return c

    def legal_district_cells(self, h):
        out = {}
        for city in h.cities:
            for cx, cy in [city.heart] + list(city.districts):
                for dx, dy in ORTHO:
                    x, y = cx + dx, cy + dy
                    if self.plain_own(h, x, y) and (x, y) not in out:
                        out[(x, y)] = city
        return out

    # --- state changes ----------------------------------------------------
    def found_city(self, h, pos):
        city = City(pos)
        h.cities.append(city)
        self.cell[pos[1]][pos[0]] = (h.id, city, "heart")
        self.owner[pos[1]][pos[0]] = h.id
        self.claim(h, pos, FOUND_OFFSETS[FOUND_REACH] if len(h.cities) > 1 else R3)

    def place(self, h, city, pos, kind):
        self.cell[pos[1]][pos[0]] = (h.id, city, kind)
        city.districts[pos] = kind
        self.claim(h, pos)

    def basic_price(self, h):
        nd = sum(len(c.districts) for c in h.cities)
        return 1 + nd // PRICE_STEP

    def settle_price(self, h):
        extra = (len(h.cities) - 1) * SETTLE_RISE
        return {"grain": 2 + extra, "wood": 2 + extra, "stone": 1 + extra}

    def can_afford(self, h, cost):
        deficit = sum(max(0, cost.get(g, 0) - h.goods[g]) for g in GOODS)
        surplus = sum(max(0, h.goods[g] - cost.get(g, 0)) // 3 for g in GOODS)
        return surplus >= deficit

    def pay(self, h, cost):
        for g in GOODS:
            while h.goods[g] < cost.get(g, 0):
                donor = max((d for d in GOODS if d != g), key=lambda d: h.goods[d] - cost.get(d, 0))
                h.goods[donor] -= 3
                h.goods[g] += 1
        for g in GOODS:
            h.goods[g] -= cost.get(g, 0)

    def collect(self, h):
        inc = 0
        for city in h.cities:
            for g in GOODS:
                h.goods[g] += 1
            inc += 3
            for pos, kind in city.districts.items():
                if kind in KIND_TERRAIN:
                    y = self.yield_at(h, pos, kind)
                    h.goods[TERRAIN_GOOD[KIND_TERRAIN[kind]]] += y
                    inc += y
        h.income_last = inc

    def house_yield_total(self, h):
        tot = 0
        for city in h.cities:
            tot += 3
            for pos, kind in city.districts.items():
                if kind in KIND_TERRAIN:
                    tot += self.yield_at(h, pos, kind)
        return tot

    def crowns(self, h):
        cells = sum(1 for row in self.owner for o in row if o == h.id)
        c = cells // 3 + len(h.cities) + h.renown
        for city in h.cities:
            for pos, kind in city.districts.items():
                if kind == "monument":
                    c += self.monument_crowns(h, pos)
        return c

    def cells_of(self, h):
        return sum(1 for row in self.owner for o in row if o == h.id)

    # --- war --------------------------------------------------------------
    def defence(self, pos):
        x, y = pos
        cc = self.cell[y][x]
        base = 1 if cc is None else (5 if cc[2] == "heart" else 3)
        if self.terrain[y][x] in (FOREST, HILLS):
            base += 1
        return base

    def touches_own(self, h, pos):
        px, py = pos
        return any(self.inb(px + dx, py + dy) and self.owner[py + dy][px + dx] == h.id for dx, dy in ORTHO)

    def reachable_city_cells(self, h):
        out = set()
        for y in range(self.n):
            for x in range(self.n):
                cc = self.cell[y][x]
                if cc and cc[0] != h.id and self.touches_own(h, (x, y)):
                    out.add((x, y))
        return out

    def siege_targets(self, h, start_reach):
        """Returns list of (pos, is_district, abandoned_count)."""
        out = []
        for y in range(self.n):
            for x in range(self.n):
                o = self.owner[y][x]
                if o == -1 or o == h.id or not self.touches_own(h, (x, y)):
                    continue
                cc = self.cell[y][x]
                if cc is None:
                    if self.defence((x, y)) < SIEGE_STRENGTH:
                        out.append(((x, y), False, 0))
                elif cc[2] != "heart" and (x, y) in start_reach and self.defence((x, y)) < SIEGE_STRENGTH:
                    out.append(((x, y), True, self.abandoned_if_razed(cc[1], (x, y))))
        return out

    def best_siege_after_foothold(self, h):
        """Best (March this turn, Siege next turn) pair: value of the Siege on a
        rival district that touches a rival plain meadow cell a March can take now."""
        best = None
        for y in range(self.n):
            for x in range(self.n):
                o = self.owner[y][x]
                if o in (-1, h.id) or self.cell[y][x] is not None:
                    continue
                if self.terrain[y][x] != MEADOW or not self.touches_own(h, (x, y)):
                    continue
                for dx, dy in ORTHO:
                    tx, ty = x + dx, y + dy
                    if not self.inb(tx, ty):
                        continue
                    cc = self.cell[ty][tx]
                    if cc and cc[0] == o and cc[2] != "heart" and self.defence((tx, ty)) < SIEGE_STRENGTH:
                        v = 1 + 2 / 3 + 0.5 * self.abandoned_if_razed(cc[1], (tx, ty))
                        if best is None or v > best:
                            best = v
        return best

    def connected(self, city, removed):
        seen = {city.heart}
        stack = [city.heart]
        members = set(city.districts) - {removed}
        while stack:
            cx, cy = stack.pop()
            for dx, dy in ORTHO:
                p = (cx + dx, cy + dy)
                if p in members and p not in seen:
                    seen.add(p)
                    stack.append(p)
        return members - seen

    def abandoned_if_razed(self, city, pos):
        return len(self.connected(city, pos))

    def siege(self, h, pos, is_district):
        x, y = pos
        victim = self.houses[self.owner[y][x]]
        if is_district:
            city = self.cell[y][x][1]
            lost = self.connected(city, pos)
            del city.districts[pos]
            for p in lost:
                del city.districts[p]
                self.cell[p[1]][p[0]] = None
            self.cell[y][x] = None
            h.renown += 1
        self.owner[y][x] = h.id

    # --- policy -----------------------------------------------------------
    def wy(self):
        return 0.5 * (ROUNDS - self.round + 1) / ROUNDS

    def best_basic(self, h, kinds, legal, exclude=None):
        best = None
        wy = self.wy()
        claims = {pos: self.claim_count(pos) for pos in legal}
        for pos, city in legal.items():
            if pos == exclude:
                continue
            base = claims[pos] / 3 - self.own_monuments_near(h, pos)
            for kind in kinds:
                s = base + wy * self.yield_at(h, pos, kind) * 2
                if best is None or s > best[0]:
                    best = (s, kind, pos, city)
        return best

    def best_monument(self, h, legal):
        best = None
        for pos, city in legal.items():
            s = self.monument_crowns(h, pos) + self.claim_count(pos) / 3 - self.own_monuments_near(h, pos)
            if best is None or s > best[0]:
                best = (s, pos, city)
        return best

    def best_settle(self, h):
        city_cells = [(x, y) for y in range(self.n) for x in range(self.n) if self.cell[y][x]]
        blocked = set()
        for cx, cy in city_cells:
            for dx, dy in R3:
                blocked.add((cx + dx, cy + dy))
        hx, hy = h.cities[0].heart
        best = None
        for y in range(self.n):
            for x in range(self.n):
                if (x, y) in blocked or not self.land(x, y) or self.owner[y][x] not in (-1, h.id):
                    continue
                c = self.claim_count((x, y), FOUND_OFFSETS[FOUND_REACH])
                d = abs(x - hx) + abs(y - hy)
                key = (c, -d)
                if best is None or key > best[0]:
                    best = (key, (x, y))
        if best is None:
            return None
        c = best[0][0]
        return (c / 3 + 1 + 3 * self.wy() * 2 + 0.5, best[1])

    def opening_hand(self, h):
        legal = self.legal_district_cells(h)
        farm = self.best_basic(h, ["farm"], legal)
        other = self.best_basic(h, ["farm", "lumber", "quarry"], legal, exclude=farm[2])
        h.hand = ["farm", other[1]]
        if BANNER_ROUND <= 1:
            self.deal_banner(h)

    def deal_banner(self, h):
        if h.banner == "builder":
            h.hand.append("monument")
        elif h.banner == "expander":
            if EXPANDER_BASIC:
                legal = self.legal_district_cells(h)
                b = self.best_basic(h, ["farm", "lumber", "quarry"], legal)
                h.hand.append(b[1] if b else "farm")
            else:
                h.hand.append("settle")
        elif h.banner == "warlord":
            h.hand.append("siege")

    def take_turn(self, h):
        if self.round == BANNER_ROUND and BANNER_ROUND > 1:
            self.deal_banner(h)
        self.collect(h)
        start_reach = self.reachable_city_cells(h) if "siege" in h.hand or self.round >= 15 else set()
        plays = PLAYS
        if self.round >= 15:
            legal = self.legal_district_cells(h)
            bm = self.best_monument(h, legal)
            targets = [t for t in self.siege_targets(h, start_reach) if t[1]]
            bs = max((1 + 2 / 3 + 0.5 * t[2] for t in targets), default=None)
            bf = self.best_siege_after_foothold(h)
            self.late_options.append((self.round, bm[0] if bm else 0, bs, bf))
        while plays > 0:
            legal = self.legal_district_cells(h)
            options = []
            for card in set(h.hand):
                if card in KIND_TERRAIN:
                    b = self.best_basic(h, [card], legal)
                    if b:
                        options.append((b[0], "play", card, b))
                elif card == "monument":
                    b = self.best_monument(h, legal)
                    if b:
                        options.append((b[0], "play", card, b))
                elif card == "settle":
                    b = self.best_settle(h)
                    if b:
                        options.append((b[0], "play", card, b))
                elif card == "siege":
                    for pos, is_d, ab in self.siege_targets(h, start_reach):
                        s = (1 + 2 / 3 + 0.5 * ab) if is_d else 2 / 3
                        options.append((s, "play", card, (s, pos, is_d)))
            price = self.basic_price(h)
            cost = {"grain": price, "wood": price}
            if len(h.hand) < HAND_CAP and self.can_afford(h, cost):
                b = self.best_basic(h, ["farm", "lumber", "quarry"], legal)
                if b:
                    options.append((b[0] - 0.01, "buy", b[1], b))
            if SETTLE_PILE and len(h.hand) < HAND_CAP and self.can_afford(h, self.settle_price(h)):
                b = self.best_settle(h)
                if b:
                    options.append((b[0] - 0.01, "buy", "settle", b))
            if not options:
                break
            options.sort(key=lambda o: o[0], reverse=True)
            s, act, card, data = options[0]
            if s <= 0.05:
                break
            if act == "buy":
                self.pay(h, self.settle_price(h) if card == "settle" else cost)
                h.hand.append(card)
            h.hand.remove(card)
            if card in KIND_TERRAIN:
                self.place(h, data[3], data[2], card)
            elif card == "monument":
                self.place(h, data[2], data[1], card)
            elif card == "settle":
                self.found_city(h, data[1])
            elif card == "siege":
                self.siege(h, data[1], data[2])
                h.siege_round = self.round
            plays -= 1
        # fill hand with cheap basics when goods allow and hand is empty
        # (kept for next turn) — modest: only if hand empty and price low
        if not h.hand:
            price = self.basic_price(h)
            cost = {"grain": price, "wood": price}
            if self.can_afford(h, cost):
                legal = self.legal_district_cells(h)
                b = self.best_basic(h, ["farm", "lumber", "quarry"], legal)
                if b:
                    self.pay(h, cost)
                    h.hand.append(b[1])

    def open_fraction(self):
        land = 0
        open_ = 0
        for y in range(self.n):
            for x in range(self.n):
                if self.land(x, y):
                    land += 1
                    if self.owner[y][x] == -1:
                        open_ += 1
        return open_ / land

    def run(self):
        for r in range(1, ROUNDS + 1):
            self.round = r
            first = (r - 1) % self.nh
            order = [self.houses[(first + i) % self.nh] for i in range(self.nh)]
            for h in order:
                self.take_turn(h)
            snap = {"round": r, "open": self.open_fraction(), "houses": []}
            for seat, h in enumerate(self.houses):
                snap["houses"].append({
                    "seat": seat, "banner": h.banner, "cells": self.cells_of(h),
                    "districts": sum(len(c.districts) for c in h.cities),
                    "cities": len(h.cities), "goods": sum(h.goods.values()),
                    "income": self.house_yield_total(h), "price": 2 * self.basic_price(h),
                    "crowns": self.crowns(h), "renown": h.renown,
                })
            self.stats.append(snap)
        return self


def mean(xs):
    return st.mean(xs) if xs else float("nan")


def run_set(nh, seeds, banner_pool):
    games = []
    rng = random.Random(1234 + nh)
    for s in range(seeds):
        pool = banner_pool[:]
        rng.shuffle(pool)
        banners = pool[:nh]
        games.append(Game(s, banners).run())
    return games


def report_growth(games, nh):
    print(f"\n=== {nh} houses, board {BOARD_FOR[nh]}x{BOARD_FOR[nh]}, {len(games)} seeds ===")
    print(f"{'round':>5} {'open%':>6} {'cells':>6} {'distr':>6} {'d/turn':>6} {'cities':>6} {'income':>7} {'price':>6} {'held':>6} {'crowns':>7}")
    for r in (1, 2, 5, 10, 15, 20):
        rows = [g.stats[r - 1] for g in games]
        hs = [h for row in rows for h in row["houses"]]
        prev = [h for g in games for h in g.stats[r - 2]["houses"]] if r > 1 else None
        dpt = mean([h['districts'] for h in hs]) - (mean([h['districts'] for h in prev]) if prev else 0)
        print(f"{r:>5} {100*mean([row['open'] for row in rows]):>6.0f} {mean([h['cells'] for h in hs]):>6.1f} "
              f"{mean([h['districts'] for h in hs]):>6.1f} {dpt:>6.2f} {mean([h['cities'] for h in hs]):>6.2f} "
              f"{mean([h['income'] for h in hs]):>7.1f} {mean([h['price'] for h in hs]):>6.1f} "
              f"{mean([h['goods'] for h in hs]):>6.1f} {mean([h['crowns'] for h in hs]):>7.1f}")


def report_banners(games):
    print("\n--- crowns by banner (4 houses) ---")
    print(f"{'banner':>9} {'r5':>6} {'r10':>6} {'r20':>6} {'cells20':>8} {'renown':>7}")
    for b in ("builder", "expander", "warlord", "none"):
        by = {r: [] for r in (5, 10, 20)}
        cells = []
        ren = []
        for g in games:
            for r in by:
                by[r] += [h["crowns"] for h in g.stats[r - 1]["houses"] if h["banner"] == b]
            cells += [h["cells"] for h in g.stats[19]["houses"] if h["banner"] == b]
            ren += [h["renown"] for h in g.stats[19]["houses"] if h["banner"] == b]
        print(f"{b:>9} {mean(by[5]):>6.1f} {mean(by[10]):>6.1f} {mean(by[20]):>6.1f} {mean(cells):>8.1f} {mean(ren):>7.2f}")
    sr = [h.siege_round for g in games for h in g.houses if h.banner == "warlord" and h.siege_round]
    held = sum(1 for g in games for h in g.houses if h.banner == "warlord" and not h.siege_round)
    print(f"warlord Siege played in round {mean(sr):.1f} on average; never played in {held} of "
          f"{sum(1 for g in games for h in g.houses if h.banner == 'warlord')} games")
    print("\n--- crowns by seat at round 20 (rotation check) ---")
    for seat in range(4):
        print(f"seat {seat}: {mean([h['crowns'] for g in games for h in g.stats[19]['houses'] if h['seat'] == seat]):.1f}")


def report_late(games):
    print("\n--- late game (rounds 15-20): best Monument vs best Siege-on-district per play ---")
    opts = [o for g in games for o in g.late_options]
    mon = [o[1] for o in opts]
    sie = [o[2] for o in opts if o[2] is not None]
    print(f"turn starts measured: {len(opts)}")
    print(f"best Monument placement, crowns per play: mean {mean(mon):.2f}, median {st.median(mon):.2f}")
    print(f"a Siege on a reachable rival district exists at {100*len(sie)/len(opts):.0f}% of turn starts")
    if sie:
        print(f"its value when it exists (renown 1 + 2/3 + 0.5 per abandoned district): mean {mean(sie):.2f}")
    foot = [o[3] for o in opts if o[3] is not None]
    print(f"a March foothold now + Siege next turn is available at {100*len(foot)/len(opts):.0f}% of turn starts; "
          f"Siege value then: mean {mean(foot):.2f} (two plays incl. the March: {mean([(f + 2/3)/2 for f in foot]):.2f} per play)")
    wins = sum(1 for o in opts if (o[2] is not None and o[2] >= o[1]) or (o[3] is not None and (o[3] + 2/3)/2 >= o[1]))
    print(f"war is worth at least as much per play as the best Monument at {100*wins/len(opts):.0f}% of turn starts")


if __name__ == "__main__":
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    if "--found2" in sys.argv:
        FOUND_REACH = 2
    if "--reach1" in sys.argv:
        MONUMENT_MODE = "reach1"
    for a in sys.argv:
        if a.startswith("--step="):
            PRICE_STEP = int(a.split("=")[1])
        if a.startswith("--banner-round="):
            BANNER_ROUND = int(a.split("=")[1])
        if a.startswith("--settle-rise="):
            SETTLE_RISE = int(a.split("=")[1])
    if "--settle-pile" in sys.argv:
        SETTLE_PILE = True
    if "--settle-banner" in sys.argv:
        EXPANDER_BASIC = False
    print(f"variant: founded heart claims reach {FOUND_REACH}, Monument scores {MONUMENT_MODE}, "
          f"price step {PRICE_STEP}, banner card dealt round {BANNER_ROUND}, "
          f"settle pile {SETTLE_PILE} (rise {SETTLE_RISE}), expander basic {EXPANDER_BASIC}")
    g4 = run_set(4, seeds, ["builder", "expander", "warlord", "none"])
    report_growth(g4, 4)
    report_banners(g4)
    report_late(g4)
    g3 = run_set(3, seeds // 2, ["builder", "expander", "warlord", "none"])
    report_growth(g3, 3)
    g2 = run_set(2, seeds // 2, ["builder", "expander", "warlord", "none"])
    report_growth(g2, 2)
    # terrain mix sanity
    cnt = defaultdict(int)
    for g in g4:
        for row in g.terrain:
            for t in row:
                cnt[t] += 1
    tot = sum(g.n * g.n for g in g4)
    print(f"\nterrain mix (all 4-house seeds): meadow {100*cnt[MEADOW]/tot:.0f}% forest {100*cnt[FOREST]/tot:.0f}% "
          f"hills {100*cnt[HILLS]/tot:.0f}% water {100*cnt[WATER]/tot:.0f}%")
