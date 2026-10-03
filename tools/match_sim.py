"""Match simulation of the DomiVale rules as written in DESIGN.md.

Where growth_sim.py models growth alone, this one plays the whole base set:
the market row and deck, basic piles, every card in section 6.2, war with
captures of territory, districts and hearts, fallen land, renown and crowns.
Greedy bots with the three temperaments play 20 rounds on boards scaled to the
house count. The defaults are the rules as the design states them; the figures
in DESIGN.md section 13 under "What the match simulation measures" come from
running this with no flags.

    python3 tools/match_sim.py [seeds] [flags]

seeds is the number of four-house boards (default 48); two- and three-house
runs use half as many. Flags switch to variants so a candidate rule can be
measured against the baseline:

    --step=N              basic price rises every N districts (default 3)
    --all-prices-rise     every card's price rises with the step, not only basics
    --abandon-renown      renown also for each district abandoned by a capture
    --district-reach=N    a district claims reach N; hearts keep reach 3
    --held-bonus          a captured cell has +1 defence until its taker's next turn
    --land-per=N          1 crown per N cells owned (default 3)
    --renown=D,H          renown per district razed / heart taken (default 1,1)
    --no-denial           bots never buy a row card only to deny it
    --jobs=N              worker processes (default: all cores)

Modelled: scaled boards, reach-3 claiming, districts and their yields, the
rising basic and Settle prices, 3 plays and 2 row buys a turn, the hand cap,
the 40-card deck with discard recycling, bank trading (2 for 1 with a Market),
the rotating first seat, opening hands and banner cards, Walls, Barracks,
Monuments, Markets, March and Siege with stacking, terrain defence, the
start-of-turn rule for city cells, abandonment, heart capture with the land
that follows it, elimination and fallen land, all crown sources.

Not modelled: height. Bots do not plan more than one turn ahead except for
taking a foothold beside a city cell they mean to besiege.
"""
import random
import statistics as st
import sys
from collections import Counter, defaultdict
from multiprocessing import Pool

MEADOW, FOREST, HILLS, WATER = 0, 1, 2, 3
GOODS = ("grain", "wood", "stone")
KIND_TERRAIN = {"farm": MEADOW, "lumber": FOREST, "quarry": HILLS}
TERRAIN_GOOD = {MEADOW: "grain", FOREST: "wood", HILLS: "stone"}
BASICS = ("farm", "lumber", "quarry")
MILITARY = ("march", "siege")

ROUNDS = 20
BOARD_FOR = {2: 22, 3: 27, 4: 32}
PLAYS = 3
ROW_BUYS = 2
HAND_CAP = 5
ROW_SIZE = 5
STRENGTH = {"march": 2, "siege": 4}
WALLS_BONUS = 2
BARRACKS_BONUS = 1
PRICE = {
    "market": {"grain": 2, "wood": 2},
    "walls": {"stone": 3},
    "barracks": {"grain": 2, "wood": 1, "stone": 1},
    "monument": {"wood": 2, "stone": 3},
    "settle": {"grain": 2, "wood": 2, "stone": 1},
    "march": {"grain": 1, "wood": 1},
    "siege": {"grain": 2, "stone": 2},
}
DECK = {"settle": 6, "march": 10, "siege": 6, "market": 5, "walls": 5, "barracks": 4, "monument": 4}
START_GOODS = {"grain": 2, "wood": 2, "stone": 1}

# Tunables. The defaults are the rules in DESIGN.md; flags change them.
PRICE_STEP = 3
SETTLE_RISE = 1
LAND_PER = 3
RENOWN_DISTRICT = 1
RENOWN_HEART = 1
RENOWN_ABANDONED = 0
DISTRICT_REACH = 3
HELD_BONUS = 0
ALL_PRICES_RISE = False
DENIAL = True

# Temperament weights on the bots' value estimates.
TEMPER = {
    "builder": dict(yield_=1.3, claim=1.0, war=0.5, walls=1.5, monument=1.3, market=1.2, settle=0.9, barracks=0.5),
    "expander": dict(yield_=1.0, claim=1.3, war=0.8, walls=0.7, monument=0.9, market=0.9, settle=1.5, barracks=0.8),
    "warlord": dict(yield_=0.9, claim=1.0, war=1.6, walls=0.8, monument=0.8, market=0.8, settle=0.9, barracks=1.6),
    "none": dict(yield_=1.0, claim=1.0, war=1.0, walls=1.0, monument=1.0, market=1.0, settle=1.0, barracks=1.0),
}
MIN_VALUE_PER_PLAY = 0.1


def reach_offsets(r):
    return [(dx, dy) for dx in range(-r, r + 1) for dy in range(-r, r + 1)
            if dx * dx + dy * dy <= (r + 0.5) ** 2]


R1 = reach_offsets(1)
R2 = reach_offsets(2)
R3 = reach_offsets(3)
ORTHO = [(1, 0), (-1, 0), (0, 1), (0, -1)]
REACH = {1: R1, 2: R2, 3: R3}


# --- board ---------------------------------------------------------------

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

    def cells(self):
        return [self.heart] + list(self.districts)


class House:
    def __init__(self, hid, banner):
        self.id = hid
        self.banner = banner
        self.w = TEMPER[banner]
        self.goods = dict(START_GOODS)
        self.hand = []
        self.cities = []
        self.renown = 0
        self.income_last = 0
        self.turns = 0
        self.alive = True
        # bookkeeping for the report
        self.played = Counter()
        self.bought_row = Counter()
        self.denial_buys = 0
        self.settles_dead = 0
        self.hearts_taken = 0
        self.spent = 0
        self.short_rounds = []  # rounds whose best option was a buy it could not pay for

    def markets(self):
        return sum(1 for c in self.cities for k in c.districts.values() if k == "market")

    def districts_count(self):
        return sum(len(c.districts) for c in self.cities)


class Game:
    def __init__(self, seed, banners):
        self.seed = seed
        self.rng = random.Random(seed)
        self.nh = len(banners)
        self.n = BOARD_FOR[self.nh]
        n = self.n
        while True:
            self.terrain = make_board(n, self.rng)
            starts = start_positions(n, self.nh)
            if all(self.terrain[y][x] != WATER for x, y in starts):
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
        self.land_cells = sum(1 for row in self.terrain for t in row if t != WATER)
        self.owner = [[-1] * n for _ in range(n)]
        self.cell = [[None] * n for _ in range(n)]  # (house id, city, kind)
        self.owned = [set() for _ in banners]
        self.captured = {}  # pos -> (taker id, taker turns) for the held bonus
        self.houses = [House(i, b) for i, b in enumerate(banners)]
        self.round = 0
        self.stats = []
        self.heart_falls = []  # (round, attacker banner, victim banner, eliminated)
        self.heart_chances = 0  # turn starts with a rival heart reachable
        self.heart_conversions = 0
        self.foothold_retakes = 0
        self.plays_by_phase = {"early": Counter(), "late": Counter()}
        self.settle_rounds = []
        self.full_round = None
        self.deck = [k for k, c in DECK.items() for _ in range(c)]
        self.rng.shuffle(self.deck)
        self.discard = []
        self.row = []
        self.settles_seen = 0
        self.refill_row()
        for h, (x, y) in zip(self.houses, starts):
            self.found_city(h, (x, y))
        for h in self.houses:
            self.opening_hand(h)

    # --- geometry -------------------------------------------------------
    def inb(self, x, y):
        return 0 <= x < self.n and 0 <= y < self.n

    def land(self, x, y):
        return self.terrain[y][x] != WATER

    def plain_own(self, h, x, y):
        return self.inb(x, y) and self.owner[y][x] == h.id and self.cell[y][x] is None

    def rem(self):
        return (ROUNDS - self.round + 1) / ROUNDS

    # --- claiming -------------------------------------------------------
    def claim(self, h, pos, offsets):
        px, py = pos
        for dx, dy in offsets:
            x, y = px + dx, py + dy
            if self.inb(x, y) and self.land(x, y) and self.owner[y][x] == -1:
                self.set_owner((x, y), h.id)

    def claim_count(self, pos, offsets):
        px, py = pos
        c = 0
        for dx, dy in offsets:
            x, y = px + dx, py + dy
            if self.inb(x, y) and self.land(x, y) and self.owner[y][x] == -1:
                c += 1
        return c

    def set_owner(self, pos, hid):
        x, y = pos
        old = self.owner[y][x]
        if old >= 0:
            self.owned[old].discard(pos)
        self.owner[y][x] = hid
        if hid >= 0:
            self.owned[hid].add(pos)

    # --- yields and crowns ----------------------------------------------
    def yield_at(self, h, pos, kind):
        t = KIND_TERRAIN[kind]
        px, py = pos
        return sum(1 for dx, dy in ORTHO
                   if self.plain_own(h, px + dx, py + dy) and self.terrain[py + dy][px + dx] == t)

    def monument_crowns(self, h, pos):
        px, py = pos
        return sum(1 for dx, dy in ORTHO if self.plain_own(h, px + dx, py + dy))

    def crown_parts(self, h):
        if not h.alive:
            return {"land": 0, "hearts": 0, "markets": 0, "monuments": 0, "renown": h.renown}
        parts = {"land": len(self.owned[h.id]) // LAND_PER, "hearts": len(h.cities),
                 "markets": 0, "monuments": 0, "renown": h.renown}
        for city in h.cities:
            for pos, kind in city.districts.items():
                if kind == "monument":
                    parts["monuments"] += self.monument_crowns(h, pos)
                elif kind == "market":
                    parts["markets"] += 1
        return parts

    def crowns(self, h):
        return sum(self.crown_parts(h).values())

    def income_total(self, h):
        tot = 0
        for city in h.cities:
            tot += 3
            for pos, kind in city.districts.items():
                if kind in KIND_TERRAIN:
                    tot += self.yield_at(h, pos, kind)
        return tot

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

    # --- prices and goods -----------------------------------------------
    def basic_price(self, h):
        step = 1 + h.districts_count() // PRICE_STEP
        return {"grain": step, "wood": step}

    def price(self, h, card):
        if card in BASICS:
            return self.basic_price(h)
        p = dict(PRICE[card])
        if card == "settle":
            extra = (len(h.cities) - 1) * SETTLE_RISE
            for g in GOODS:
                p[g] = p.get(g, 0) + extra
        if ALL_PRICES_RISE:
            extra = h.districts_count() // PRICE_STEP
            for g in list(p):
                p[g] += extra
        return p

    def trade_rate(self, h):
        return 2 if h.markets() else 3

    def can_afford(self, h, cost):
        rate = self.trade_rate(h)
        deficit = sum(max(0, cost.get(g, 0) - h.goods[g]) for g in GOODS)
        surplus = sum(max(0, h.goods[g] - cost.get(g, 0)) // rate for g in GOODS)
        return surplus >= deficit

    def pay(self, h, cost):
        rate = self.trade_rate(h)
        for g in GOODS:
            while h.goods[g] < cost.get(g, 0):
                donor = max((d for d in GOODS if d != g), key=lambda d: h.goods[d] - cost.get(d, 0))
                h.goods[donor] -= rate
                h.goods[g] += 1
        for g in GOODS:
            h.goods[g] -= cost.get(g, 0)
        h.spent += sum(cost.values())

    # --- market ---------------------------------------------------------
    def draw(self):
        if not self.deck:
            if not self.discard:
                return None
            self.deck = self.discard
            self.discard = []
            self.rng.shuffle(self.deck)
        return self.deck.pop()

    def refill_row(self):
        while len(self.row) < ROW_SIZE:
            c = self.draw()
            if c is None:
                break
            if c == "settle":
                self.settles_seen += 1
            self.row.append(c)

    # --- war: defence and targets ---------------------------------------
    def walls_near(self, hid, pos):
        px, py = pos
        for dx, dy in R1:
            x, y = px + dx, py + dy
            if self.inb(x, y):
                cc = self.cell[y][x]
                if cc and cc[0] == hid and cc[2] == "walls":
                    return True
        return False

    def barracks_near(self, hid, pos):
        px, py = pos
        for dx, dy in R3:
            x, y = px + dx, py + dy
            if self.inb(x, y):
                cc = self.cell[y][x]
                if cc and cc[0] == hid and cc[2] == "barracks":
                    return True
        return False

    def defence(self, pos):
        x, y = pos
        o = self.owner[y][x]
        if o == -1:
            return 0
        cc = self.cell[y][x]
        owner = self.houses[o]
        if cc is None:
            d = 1
        elif cc[2] == "heart":
            d = 5
        else:
            d = 3
        if self.terrain[y][x] in (FOREST, HILLS):
            d += 1
        if owner.alive and self.walls_near(o, pos):
            d += WALLS_BONUS
        if HELD_BONUS:
            rec = self.captured.get(pos)
            if rec and rec[0] == o and owner.turns == rec[1]:
                d += HELD_BONUS
        return d

    def touches_own(self, h, pos):
        px, py = pos
        return any(self.inb(px + dx, py + dy) and self.owner[py + dy][px + dx] == h.id for dx, dy in ORTHO)

    def border_cells(self, h):
        out = set()
        for (x, y) in self.owned[h.id]:
            for dx, dy in ORTHO:
                nx, ny = x + dx, y + dy
                if self.inb(nx, ny) and self.land(nx, ny) and self.owner[ny][nx] != h.id:
                    out.add((nx, ny))
        return out

    def reachable_city_cells(self, h):
        return {p for p in self.border_cells(h) if self.cell[p[1]][p[0]] is not None}

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

    def city_transfer(self, victim, city):
        """Plain cells of the victim that follow the city when its heart falls."""
        near = set()
        for cx, cy in city.cells():
            for dx, dy in R3:
                near.add((cx + dx, cy + dy))
        other = set()
        for c in victim.cities:
            if c is city:
                continue
            for cx, cy in c.cells():
                for dx, dy in R3:
                    other.add((cx + dx, cy + dy))
        return [p for p in near if p in self.owned[victim.id] and self.cell[p[1]][p[0]] is None and p not in other]

    def combo(self, hand, plays_left, need, is_city):
        """Cheapest set of military cards from hand whose strength beats `need`.
        Returns (plays, marches, sieges) or None."""
        m = hand.count("march")
        s = hand.count("siege")
        if is_city:
            m = 0
        best = None
        for k in range(1, plays_left + 1):
            for sieges in range(0, min(k, s) + 1):
                marches = k - sieges
                if marches > m:
                    continue
                if 2 * marches + 4 * sieges > need:
                    cand = (k, marches, sieges)
                    if best is None or cand[2] < best[2]:
                        best = cand
            if best:
                return best
        return None

    # --- values -------------------------------------------------------
    def yield_value(self, h, y):
        if y <= 0:
            return 0.0
        return y * self.rem() * 1.5 * min(1.0, 12 / max(1, h.income_last))

    def can_siege_soon(self, h):
        return "siege" in h.hand or "siege" in self.row or h.banner == "warlord"

    def capture_value(self, h, pos, start_reach):
        x, y = pos
        o = self.owner[y][x]
        cc = self.cell[y][x]
        w = h.w["war"]
        if o == -1:
            return 1 / LAND_PER
        victim = self.houses[o]
        rem = self.rem()
        if cc is None:
            v = 1 / LAND_PER + (1 / LAND_PER if victim.alive else 0)
            if victim.alive:
                for dx, dy in ORTHO:
                    nx, ny = x + dx, y + dy
                    if not self.inb(nx, ny):
                        continue
                    nc = self.cell[ny][nx]
                    if nc and nc[0] == o:
                        kind = nc[2]
                        if kind in KIND_TERRAIN and KIND_TERRAIN[kind] == self.terrain[y][x]:
                            v += 0.35 * rem
                        elif kind == "monument":
                            v += 1.0
                        if (nx, ny) not in start_reach and self.can_siege_soon(h):
                            v += (1.2 if kind == "heart" else 0.5) * w
                    if nc and nc[0] == h.id:
                        v += 1.0 if nc[2] == "heart" else 0.5  # retake a foothold
            return v * w
        kind = cc[2]
        city = cc[1]
        if kind == "heart":
            transfer = self.city_transfer(victim, city)
            v = 1 + RENOWN_HEART + 2 * len(transfer) / LAND_PER + 0.3 * len(city.districts)
            for p, k in city.districts.items():
                if k == "monument":
                    v += self.monument_crowns(victim, p)
                elif k == "market":
                    v += 1
            if len(victim.cities) == 1:
                v += 2
            return v * w
        ab = len(self.connected(city, pos))
        v = 2 / LAND_PER + RENOWN_DISTRICT + (0.4 + RENOWN_ABANDONED) * ab
        if kind == "monument":
            v += self.monument_crowns(victim, pos)
        elif kind == "market":
            v += 1
        elif kind in ("walls", "barracks"):
            v += 0.5
        elif kind in KIND_TERRAIN:
            v += 0.25 * rem * self.yield_at(victim, pos, kind)
        for dx, dy in ORTHO:
            nx, ny = x + dx, y + dy
            if self.inb(nx, ny):
                nc = self.cell[ny][nx]
                if nc and nc[0] == o and nc[2] == "heart":
                    v += 1.0
        return v * w

    def attack_options(self, h, hand, plays_left, start_reach):
        out = []
        if "march" not in hand and "siege" not in hand:
            return out
        for pos in self.border_cells(h):
            cc = self.cell[pos[1]][pos[0]]
            is_city = cc is not None
            if is_city and pos not in start_reach:
                continue
            need = self.defence(pos) - (BARRACKS_BONUS if self.barracks_near(h.id, pos) else 0)
            c = self.combo(hand, plays_left, need, is_city)
            if c is None:
                continue
            v = self.capture_value(h, pos, start_reach)
            out.append((v / c[0], "attack", (pos, c), v))
        return out

    def exposed(self, h, pos):
        px, py = pos
        for dx, dy in R2:
            x, y = px + dx, py + dy
            if self.inb(x, y):
                o = self.owner[y][x]
                if o not in (-1, h.id) and self.houses[o].alive:
                    return True
        return False

    def walls_value(self, h, pos):
        px, py = pos
        v = 0.0
        for dx, dy in R1:
            x, y = px + dx, py + dy
            if not self.inb(x, y):
                continue
            cc = self.cell[y][x]
            if cc and cc[0] == h.id and not self.walls_near(h.id, (x, y)) and self.exposed(h, (x, y)):
                v += 1.0 if cc[2] == "heart" else 0.3
        if self.exposed(h, pos):
            v += 0.1
        return v

    def barracks_value(self, h, pos):
        px, py = pos
        v = 0.0
        for dx, dy in R3:
            x, y = px + dx, py + dy
            if not self.inb(x, y):
                continue
            o = self.owner[y][x]
            if o in (-1, h.id) or not self.houses[o].alive:
                continue
            cc = self.cell[y][x]
            if cc:
                v += 0.5 if cc[2] == "heart" else 0.25
            else:
                v += 0.02
        return v

    def legal_district_cells(self, h):
        out = {}
        for city in h.cities:
            for cx, cy in city.cells():
                for dx, dy in ORTHO:
                    x, y = cx + dx, cy + dy
                    if self.plain_own(h, x, y) and (x, y) not in out:
                        out[(x, y)] = city
        return out

    def place_base(self, h, pos, claims):
        """Value every district shares: land claimed, minus what the cell fed."""
        x, y = pos
        v = claims[pos] / LAND_PER * h.w["claim"] + 0.04 * claims[pos]
        lost_yield = 0
        for dx, dy in ORTHO:
            nx, ny = x + dx, y + dy
            if not self.inb(nx, ny):
                continue
            nc = self.cell[ny][nx]
            if nc and nc[0] == h.id:
                if nc[2] == "monument":
                    v -= 1.0
                elif nc[2] in KIND_TERRAIN and KIND_TERRAIN[nc[2]] == self.terrain[y][x]:
                    lost_yield += 1
        v -= self.yield_value(h, lost_yield) * h.w["yield_"]
        return v

    def best_district(self, h, kind, legal, claims):
        best = None
        for pos, city in legal.items():
            v = self.place_base(h, pos, claims)
            if kind in KIND_TERRAIN:
                v += self.yield_value(h, self.yield_at(h, pos, kind)) * h.w["yield_"]
            elif kind == "market":
                v += 1.0 * h.w["market"] + (0.3 if not h.markets() else 0.05)
            elif kind == "monument":
                v += self.monument_crowns(h, pos) * h.w["monument"]
            elif kind == "walls":
                v += self.walls_value(h, pos) * h.w["walls"]
            elif kind == "barracks":
                v += self.barracks_value(h, pos) * h.w["barracks"]
            if best is None or v > best[0]:
                best = (v, pos, city)
        return best

    def settle_blocked(self):
        blocked = set()
        for hh in self.houses:
            for city in hh.cities:
                for cx, cy in city.cells():
                    for dx, dy in R3:
                        blocked.add((cx + dx, cy + dy))
        return blocked

    def best_settle(self, h, blocked):
        best = None
        for y in range(self.n):
            for x in range(self.n):
                if (x, y) in blocked or not self.land(x, y) or self.owner[y][x] not in (-1, h.id):
                    continue
                c = self.claim_count((x, y), R3)
                if best is None or c > best[0]:
                    best = (c, (x, y))
        if best is None:
            return None
        v = (best[0] / LAND_PER * h.w["claim"] + 1 + 2.5 * self.rem() + 0.5) * h.w["settle"]
        return (v, best[1])

    def hold_value(self, h, card, blocked):
        """What a card is worth in hand for a later turn."""
        w = h.w
        if card == "siege":
            near = any(self.cell[p[1]][p[0]] is not None for p in self.border_cells(h))
            return (0.9 if near else 0.35) * w["war"]
        if card == "march":
            near = any(self.owner[p[1]][p[0]] >= 0 for p in self.border_cells(h))
            return (0.45 if near else 0.1) * w["war"]
        if card == "settle":
            return 0.8 * w["settle"] if self.best_settle(h, blocked) else 0.0
        if card == "monument":
            return 0.6 * w["monument"]
        if card == "market":
            return 0.5 * w["market"] if not h.markets() else 0.2
        if card == "walls":
            return 0.3 * w["walls"]
        if card == "barracks":
            return 0.3 * w["barracks"]
        return 0.0

    def denial_value(self, h, card, blocked):
        if not DENIAL:
            return 0.0
        if card == "settle":
            if any(r.alive and r is not h and len(r.cities) < 3 for r in self.houses) and self.open_fraction() > 0.1:
                return 0.5
        if card == "siege":
            for p in self.border_cells(h):
                o = self.owner[p[1]][p[0]]
                if o >= 0 and self.houses[o].banner == "warlord" and self.houses[o].alive:
                    return 0.4
        return 0.0

    # --- state changes ----------------------------------------------------
    def found_city(self, h, pos):
        city = City(pos)
        h.cities.append(city)
        self.cell[pos[1]][pos[0]] = (h.id, city, "heart")
        self.set_owner(pos, h.id)
        self.claim(h, pos, R3)

    def place(self, h, city, pos, kind):
        self.cell[pos[1]][pos[0]] = (h.id, city, kind)
        city.districts[pos] = kind
        self.claim(h, pos, REACH[DISTRICT_REACH])

    def capture(self, h, pos):
        x, y = pos
        o = self.owner[y][x]
        cc = self.cell[y][x]
        if cc is not None and cc[0] == h.id:
            return
        if o >= 0:
            victim = self.houses[o]
            # a rival's foothold beside one of our city cells
            if cc is None and any(self.inb(x + dx, y + dy) and self.cell[y + dy][x + dx]
                                  and self.cell[y + dy][x + dx][0] == h.id for dx, dy in ORTHO):
                self.foothold_retakes += 1
        if cc is None:
            self.set_owner(pos, h.id)
            self.captured[pos] = (h.id, h.turns)
            return
        victim = self.houses[o]
        city = cc[1]
        if cc[2] == "heart":
            transfer = self.city_transfer(victim, city)
            victim.cities.remove(city)
            h.cities.append(city)
            for p in city.cells():
                k = self.cell[p[1]][p[0]][2]
                self.cell[p[1]][p[0]] = (h.id, city, k)
                self.set_owner(p, h.id)
            for p in transfer:
                self.set_owner(p, h.id)
            h.renown += RENOWN_HEART
            h.hearts_taken += 1
            eliminated = not victim.cities
            if eliminated:
                victim.alive = False
                victim.hand = []
            self.heart_falls.append((self.round, h.banner, victim.banner, eliminated))
            return
        lost = self.connected(city, pos)
        del city.districts[pos]
        for p in lost:
            del city.districts[p]
            self.cell[p[1]][p[0]] = None
        self.cell[y][x] = None
        self.set_owner(pos, h.id)
        self.captured[pos] = (h.id, h.turns)
        h.renown += RENOWN_DISTRICT + RENOWN_ABANDONED * len(lost)

    # --- turns ------------------------------------------------------------
    def opening_hand(self, h):
        legal = self.legal_district_cells(h)
        claims = {pos: self.claim_count(pos, REACH[DISTRICT_REACH]) for pos in legal}
        farm = self.best_district(h, "farm", legal, claims)
        other = max((self.best_district(h, k, legal, claims) + (k,) for k in BASICS), key=lambda t: t[0])
        h.hand = ["farm", other[3]]
        if h.banner == "builder":
            h.hand.append("monument")
        elif h.banner == "expander":
            h.hand.append(other[3])
        elif h.banner == "warlord":
            h.hand.append("siege")
        del farm

    def play_options(self, h, hand, plays_left, start_reach, legal, claims, blocked):
        opts = []
        for card in set(hand):
            if card in BASICS or card in ("market", "walls", "barracks", "monument"):
                b = self.best_district(h, card, legal, claims)
                if b:
                    opts.append((b[0], "district", (card, b[1], b[2]), b[0]))
            elif card == "settle":
                b = self.best_settle(h, blocked)
                if b:
                    opts.append((b[0], "settle", (b[1],), b[0]))
        opts += self.attack_options(h, hand, plays_left, start_reach)
        return opts

    def take_turn(self, h):
        if not h.alive:
            return
        h.turns += 1
        self.collect(h)
        start_reach = self.reachable_city_cells(h)
        if any(self.cell[p[1]][p[0]][2] == "heart" for p in start_reach):
            self.heart_chances += 1
            hearts_before = h.hearts_taken
        else:
            hearts_before = None
        plays_left = PLAYS
        buys_left = ROW_BUYS
        phase = "late" if self.round >= 15 else "early"
        short = False
        while True:
            opts = []
            blocked_best = 0.0
            blocked = self.settle_blocked()
            if plays_left:
                legal = self.legal_district_cells(h)
                claims = {pos: self.claim_count(pos, REACH[DISTRICT_REACH]) for pos in legal}
                for o in self.play_options(h, h.hand, plays_left, start_reach, legal, claims, blocked):
                    opts.append(o + ("play", None))
                if len(h.hand) < HAND_CAP:
                    # buy a basic and play it now
                    cost = self.basic_price(h)
                    affordable = self.can_afford(h, cost)
                    best = None
                    for k in BASICS:
                        b = self.best_district(h, k, legal, claims)
                        if b and (best is None or b[0] > best[0]):
                            best = (b[0], k, b[1], b[2])
                    if best and best[0] > MIN_VALUE_PER_PLAY:
                        if affordable:
                            opts.append((best[0] - 0.01, "district", (best[1], best[2], best[3]), best[0], "buy", best[1]))
                        else:
                            blocked_best = max(blocked_best, best[0])
                    # buy a row card and play it now
                    if buys_left:
                        for card in set(self.row):
                            affordable = self.can_afford(h, self.price(h, card))
                            for o in self.play_options(h, h.hand + [card], plays_left, start_reach, legal, claims, blocked):
                                if o[1] == "district" and o[2][0] != card:
                                    continue
                                if o[1] == "settle" and card != "settle":
                                    continue
                                if o[1] == "attack":
                                    pos, c = o[2]
                                    uses = (card == "march" and c[1] > h.hand.count("march")) or \
                                           (card == "siege" and c[2] > h.hand.count("siege"))
                                    if not uses:
                                        continue
                                if affordable:
                                    opts.append((o[0] - 0.01, o[1], o[2], o[3], "buy", card))
                                else:
                                    blocked_best = max(blocked_best, o[0])
            # buy a row card to keep
            if buys_left and len(h.hand) < HAND_CAP:
                for card in set(self.row):
                    hv = self.hold_value(h, card, blocked)
                    dv = self.denial_value(h, card, blocked)
                    v = max(hv, dv)
                    if card in MILITARY and h.banner != "warlord" and len(h.hand) >= HAND_CAP - 1:
                        v *= 0.5
                    if v <= MIN_VALUE_PER_PLAY:
                        continue
                    if not self.can_afford(h, self.price(h, card)):
                        blocked_best = max(blocked_best, v)
                        continue
                    opts.append((v, "hold", (card, dv > hv), v, "buy", card))
            opts.sort(key=lambda o: o[0], reverse=True)
            if blocked_best > (opts[0][0] if opts else MIN_VALUE_PER_PLAY):
                short = True
            if not opts:
                break
            per_play, act, data, total, src, card = opts[0]
            if per_play <= MIN_VALUE_PER_PLAY:
                break
            if src == "buy":
                self.pay(h, self.price(h, card))
                h.hand.append(card)
                if card not in BASICS:
                    self.row.remove(card)
                    buys_left -= 1
                    h.bought_row[card] += 1
            if act == "hold":
                if data[1]:
                    h.denial_buys += 1
                continue
            if act == "district":
                kind, pos, city = data
                h.hand.remove(kind)
                self.place(h, city, pos, kind)
                if kind not in BASICS:
                    self.discard.append(kind)
                h.played[kind] += 1
                self.plays_by_phase[phase][kind] += 1
                plays_left -= 1
            elif act == "settle":
                h.hand.remove("settle")
                self.discard.append("settle")
                self.found_city(h, data[0])
                self.settle_rounds.append(self.round)
                h.played["settle"] += 1
                self.plays_by_phase[phase]["settle"] += 1
                plays_left -= 1
            elif act == "attack":
                pos, (k, marches, sieges) = data
                for _ in range(marches):
                    h.hand.remove("march")
                    self.discard.append("march")
                    h.played["march"] += 1
                    self.plays_by_phase[phase]["march"] += 1
                for _ in range(sieges):
                    h.hand.remove("siege")
                    self.discard.append("siege")
                    h.played["siege"] += 1
                    self.plays_by_phase[phase]["siege"] += 1
                self.capture(h, pos)
                plays_left -= k
        if hearts_before is not None and h.hearts_taken > hearts_before:
            self.heart_conversions += 1
        if short:
            h.short_rounds.append(self.round)
        self.refill_row()

    # --- measurements -------------------------------------------------------
    def open_fraction(self):
        owned = sum(len(s) for s in self.owned)
        return (self.land_cells - owned) / self.land_cells

    def thinness(self, h):
        """(districts, tips, mean city neighbours) over the house's districts."""
        tips = 0
        nb = 0
        total = 0
        for city in h.cities:
            members = set(city.cells())
            for pos in city.districts:
                total += 1
                k = sum(1 for dx, dy in ORTHO if (pos[0] + dx, pos[1] + dy) in members)
                nb += k
                if k <= 1:
                    tips += 1
        return total, tips, nb

    def walled_share(self, h):
        cells = [p for c in h.cities for p in c.cells()]
        if not cells:
            return None
        return sum(1 for p in cells if self.walls_near(h.id, p)) / len(cells)

    def snapshot(self, r):
        snap = {"round": r, "open": self.open_fraction(), "houses": []}
        for seat, h in enumerate(self.houses):
            parts = self.crown_parts(h)
            d, tips, nb = self.thinness(h)
            snap["houses"].append({
                "seat": seat, "banner": h.banner, "alive": h.alive, "cells": len(self.owned[h.id]),
                "districts": d, "tips": tips, "neighbours": nb, "cities": len(h.cities),
                "goods": sum(h.goods.values()), "income": h.income_last,
                "price": sum(self.basic_price(h).values()), "crowns": sum(parts.values()),
                "parts": parts, "hand": len(h.hand), "walled": self.walled_share(h),
            })
        self.stats.append(snap)

    def final_ranking(self):
        first = (ROUNDS - 1) % self.nh
        order = {self.houses[(first + i) % self.nh].id: i for i in range(self.nh)}
        return sorted(self.houses, key=lambda h: (self.crowns(h), len(h.cities), order[h.id]), reverse=True)

    def run(self):
        for r in range(1, ROUNDS + 1):
            self.round = r
            first = (r - 1) % self.nh
            for i in range(self.nh):
                self.take_turn(self.houses[(first + i) % self.nh])
            self.snapshot(r)
            if self.full_round is None and self.open_fraction() < 0.1:
                self.full_round = r
            if sum(1 for h in self.houses if h.alive) <= 1:
                while len(self.stats) < ROUNDS:
                    self.snapshot(len(self.stats) + 1)
                break
        for h in self.houses:
            h.settles_dead = h.hand.count("settle")
        return self.summary()

    def summary(self):
        """Plain data for the parent process."""
        ranking = self.final_ranking()
        return {
            "seed": self.seed, "nh": self.nh, "stats": self.stats,
            "winner": ranking[0].id, "ranking": [h.id for h in ranking],
            "final_crowns": {h.id: self.crowns(h) for h in self.houses},
            "heart_falls": self.heart_falls, "heart_chances": self.heart_chances,
            "heart_conversions": self.heart_conversions, "foothold_retakes": self.foothold_retakes,
            "plays_by_phase": {k: dict(v) for k, v in self.plays_by_phase.items()},
            "settles_seen": self.settles_seen, "settle_rounds": self.settle_rounds,
            "full_round": self.full_round,
            "houses": [{
                "id": h.id, "banner": h.banner, "alive": h.alive, "played": dict(h.played),
                "bought_row": dict(h.bought_row), "denial": h.denial_buys, "settles_dead": h.settles_dead,
                "hearts_taken": h.hearts_taken, "spent": h.spent, "short_rounds": h.short_rounds,
                "cities": len(h.cities), "hand": len(h.hand), "renown": h.renown,
            } for h in self.houses],
            "terrain": Counter(t for row in self.terrain for t in row),
        }


# --- running and reporting ---------------------------------------------------

def mean(xs):
    xs = list(xs)
    return st.mean(xs) if xs else float("nan")


def play_game(args):
    seed, banners, settings = args
    globals().update(settings)
    return Game(seed, banners).run()


def run_set(nh, seeds, settings, jobs):
    rng = random.Random(1234 + nh)
    pool = ["builder", "expander", "warlord", "none"]
    jobs_list = []
    for s in range(seeds):
        p = pool[:]
        rng.shuffle(p)
        jobs_list.append((s, p[:nh], settings))
    if jobs == 1:
        return [play_game(j) for j in jobs_list]
    with Pool(jobs) as pool_:
        return pool_.map(play_game, jobs_list)


def houses_at(games, r):
    return [h for g in games for h in g["stats"][r - 1]["houses"]]


def report_growth(games, nh):
    print(f"\n=== {nh} houses, board {BOARD_FOR[nh]}x{BOARD_FOR[nh]}, {len(games)} seeds ===")
    print(f"{'round':>5} {'open%':>6} {'cells':>6} {'distr':>6} {'cities':>6} {'income':>7} {'price':>6} "
          f"{'held':>6} {'hand':>5} {'crowns':>7} {'tips%':>6} {'walled%':>7}")
    for r in (1, 2, 5, 10, 15, 20):
        rows = [g["stats"][r - 1] for g in games]
        hs = [h for row in rows for h in row["houses"] if h["alive"]]
        tips = sum(h["tips"] for h in hs) / max(1, sum(h["districts"] for h in hs))
        walled = mean(h["walled"] for h in hs if h["walled"] is not None)
        print(f"{r:>5} {100*mean(row['open'] for row in rows):>6.0f} {mean(h['cells'] for h in hs):>6.1f} "
              f"{mean(h['districts'] for h in hs):>6.1f} {mean(h['cities'] for h in hs):>6.2f} "
              f"{mean(h['income'] for h in hs):>7.1f} {mean(h['price'] for h in hs):>6.1f} "
              f"{mean(h['goods'] for h in hs):>6.1f} {mean(h['hand'] for h in hs):>5.1f} "
              f"{mean(h['crowns'] for h in hs):>7.1f} {100*tips:>6.0f} {100*walled:>7.0f}")


def report_crowns(games):
    print("\n--- crowns at round 20: where they come from (per house, alive houses) ---")
    hs = [h for h in houses_at(games, 20) if h["alive"]]
    for k in ("land", "hearts", "markets", "monuments", "renown"):
        print(f"{k:>10}: {mean(h['parts'][k] for h in hs):>6.1f}")
    print("\n--- lead and result ---")
    for r in (5, 10, 15):
        decided = 0
        held = 0
        for g in games:
            hs_r = g["stats"][r - 1]["houses"]
            top = max(h["crowns"] for h in hs_r)
            leaders = [h["seat"] for h in hs_r if h["crowns"] == top]
            if len(leaders) != 1:
                continue
            decided += 1
            if leaders[0] == g["winner"]:
                held += 1
        print(f"round {r:>2} leader wins the match: {100*held/max(1,decided):>3.0f}% ({held}/{decided} games with a single leader)")
    gaps = []
    spreads = []
    for g in games:
        cs = sorted(g["final_crowns"].values(), reverse=True)
        gaps.append(cs[0] - cs[1])
        spreads.append(cs[0] - cs[-1])
    print(f"final margin, first over second: mean {mean(gaps):.1f}, median {st.median(gaps):.1f}; first over last: mean {mean(spreads):.1f}")
    # comebacks: winner's rank at round 10
    ranks = Counter()
    for g in games:
        hs10 = sorted(g["stats"][9]["houses"], key=lambda h: h["crowns"], reverse=True)
        ranks[[h["seat"] for h in hs10].index(g["winner"]) + 1] += 1
    print("winner's rank at round 10: " + ", ".join(f"{k}: {v}" for k, v in sorted(ranks.items())))


def report_war(games):
    print("\n--- war ---")
    falls = [f for g in games for f in g["heart_falls"]]
    with_fall = sum(1 for g in games if g["heart_falls"])
    elim = sum(1 for f in falls if f[3])
    print(f"heart captures: {len(falls)} in {len(games)} games ({with_fall} games with at least one); "
          f"eliminations: {elim}")
    if falls:
        print(f"  round of capture: mean {mean(f[0] for f in falls):.1f}; by attacker banner: "
              + ", ".join(f"{b}: {c}" for b, c in Counter(f[1] for f in falls).items()))
    chances = sum(g["heart_chances"] for g in games)
    conv = sum(g["heart_conversions"] for g in games)
    print(f"turn starts with a rival heart reachable: {chances}; a heart fell that turn: {conv} "
          f"({100*conv/max(1,chances):.0f}%)")
    print(f"footholds retaken (a March on a rival cell beside one's own city cell): {sum(g['foothold_retakes'] for g in games)} "
          f"({mean(g['foothold_retakes'] for g in games):.1f} per game)")
    ren = [h["renown"] for g in games for h in g["houses"]]
    print(f"renown per house at the end: mean {mean(ren):.1f}")
    for phase in ("early", "late"):
        tot = Counter()
        for g in games:
            tot.update(g["plays_by_phase"][phase])
        n = sum(tot.values())
        label = "rounds 1-14" if phase == "early" else "rounds 15-20"
        print(f"plays in {label}: " + ", ".join(f"{k} {100*v/n:.0f}%" for k, v in tot.most_common()))


def report_market(games):
    print("\n--- market ---")
    hs = [h for g in games for h in g["houses"]]
    bought = Counter()
    played = Counter()
    for h in hs:
        bought.update(h["bought_row"])
        played.update(h["played"])
    print("row cards bought per house: " + ", ".join(f"{k} {v/len(hs):.1f}" for k, v in bought.most_common()))
    print(f"denial buys per house: {mean(h['denial'] for h in hs):.1f}")
    print(f"Settles: {mean(g['settles_seen'] for g in games):.1f} reached the row per game; per house: bought "
          f"{mean(h['bought_row'].get('settle', 0) for h in hs):.2f}, played {mean(h['played'].get('settle', 0) for h in hs):.2f}, "
          f"still in hand at the end {mean(h['settles_dead'] for h in hs):.2f}; cities at the end {mean(h['cities'] for h in hs):.2f}")
    sr = [r for g in games for r in g["settle_rounds"]]
    print(f"Settles played in round 1: {sum(1 for r in sr if r == 1)/len(games):.2f} per game; "
          f"by round 5: {sum(1 for r in sr if r <= 5)/len(games):.2f}; median round of a Settle: {st.median(sr) if sr else float('nan'):.0f}")
    full = [g["full_round"] for g in games if g["full_round"]]
    print(f"open land below 10%: in {len(full)} of {len(games)} games, at round {mean(full):.1f} on average")
    parts = []
    for lo, hi in ((1, 5), (6, 10), (11, 15), (16, 20)):
        n = sum(1 for h in hs for r in h["short_rounds"] if lo <= r <= hi)
        parts.append(f"rounds {lo}-{hi}: {100*n/(len(hs)*(hi-lo+1)):.0f}%")
    print("turns where the bot's best option was a buy it could not pay for: " + ", ".join(parts))
    inc = sum(hh["income"] for g in games for s in g["stats"] for hh in s["houses"] if hh["alive"])
    spent = sum(h["spent"] for h in hs)
    print(f"goods spent over the match as a share of goods collected: {100*spent/max(1,inc):.0f}%")


def report_banners(games):
    print("\n--- by banner (4 houses) ---")
    print(f"{'banner':>9} {'r5':>6} {'r10':>6} {'r20':>6} {'wins%':>6} {'cells20':>8} {'renown':>7} {'hearts':>7} {'cities':>7}")
    for b in ("builder", "expander", "warlord", "none"):
        by = {r: [h["crowns"] for h in houses_at(games, r) if h["banner"] == b] for r in (5, 10, 20)}
        n = sum(1 for g in games for h in g["houses"] if h["banner"] == b)
        wins = sum(1 for g in games for h in g["houses"] if h["banner"] == b and h["id"] == g["winner"])
        cells = [h["cells"] for h in houses_at(games, 20) if h["banner"] == b]
        ren = [h["renown"] for g in games for h in g["houses"] if h["banner"] == b]
        hearts = [h["hearts_taken"] for g in games for h in g["houses"] if h["banner"] == b]
        cities = [h["cities"] for g in games for h in g["houses"] if h["banner"] == b]
        print(f"{b:>9} {mean(by[5]):>6.1f} {mean(by[10]):>6.1f} {mean(by[20]):>6.1f} {100*wins/max(1,n):>6.0f} "
              f"{mean(cells):>8.1f} {mean(ren):>7.2f} {mean(hearts):>7.2f} {mean(cities):>7.2f}")
    print("crowns by seat at round 20: " + ", ".join(
        f"seat {s}: {mean(h['crowns'] for h in houses_at(games, 20) if h['seat'] == s):.1f}" for s in range(4)))


def report_thinness(games):
    print("\n--- city shape (alive houses) ---")
    print(f"{'round':>5} {'tips%':>6} {'nbrs':>5}")
    for r in (5, 10, 20):
        hs = [h for h in houses_at(games, r) if h["alive"]]
        d = sum(h["districts"] for h in hs)
        print(f"{r:>5} {100*sum(h['tips'] for h in hs)/max(1,d):>6.0f} {sum(h['neighbours'] for h in hs)/max(1,d):>5.2f}")
    print("tips% is the share of districts touching only one city cell; nbrs the mean city cells a district touches.")


if __name__ == "__main__":
    seeds = 48
    jobs = None
    settings = {}
    for a in sys.argv[1:]:
        if a.isdigit():
            seeds = int(a)
        elif a.startswith("--step="):
            settings["PRICE_STEP"] = int(a.split("=")[1])
        elif a == "--all-prices-rise":
            settings["ALL_PRICES_RISE"] = True
        elif a == "--abandon-renown":
            settings["RENOWN_ABANDONED"] = 1
        elif a.startswith("--district-reach="):
            settings["DISTRICT_REACH"] = int(a.split("=")[1])
        elif a == "--held-bonus":
            settings["HELD_BONUS"] = 1
        elif a.startswith("--land-per="):
            settings["LAND_PER"] = int(a.split("=")[1])
        elif a.startswith("--renown="):
            d, hh = a.split("=")[1].split(",")
            settings["RENOWN_DISTRICT"] = int(d)
            settings["RENOWN_HEART"] = int(hh)
        elif a == "--no-denial":
            settings["DENIAL"] = False
        elif a.startswith("--jobs="):
            jobs = int(a.split("=")[1])
        else:
            sys.exit(f"unknown flag {a}")
    globals().update(settings)
    print("variant: " + (", ".join(f"{k}={v}" for k, v in settings.items()) or "baseline (the rules as written)"))
    g4 = run_set(4, seeds, settings, jobs)
    report_growth(g4, 4)
    report_crowns(g4)
    report_war(g4)
    report_market(g4)
    report_banners(g4)
    report_thinness(g4)
    g3 = run_set(3, max(2, seeds // 2), settings, jobs)
    report_growth(g3, 3)
    report_crowns(g3)
    report_war(g3)
    g2 = run_set(2, max(2, seeds // 2), settings, jobs)
    report_growth(g2, 2)
    report_crowns(g2)
    report_war(g2)
