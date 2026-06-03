const livesEl = document.getElementById('lives');
const chamberMenuEl = document.getElementById('chamberMenu');
const chamberCountEl = document.getElementById('chamberCount');
const chamberStartEl = document.getElementById('chamberStart');
const chamberJoinEl = document.getElementById('chamberJoin');
const chamberCloseEl = document.getElementById('chamberClose');
const chamberLobbyListEl = document.getElementById('chamberLobbyList');
const lobbyOverlayEl = document.getElementById('lobbyOverlay');
const lobbyCountEl = document.getElementById('lobbyCount');
const lobbyStatusEl = document.getElementById('lobbyStatus');
const lobbyHintEl = document.getElementById('lobbyHint');
const lobbyPlayersEl = document.getElementById('lobbyPlayers');
const lobbyLeaveEl = document.getElementById('lobbyLeave');
const weaponVoteEl = document.getElementById('weaponVote');
const weaponVoteCardsEl = document.getElementById('weaponVoteCards');
const weaponVoteTimerEl = document.getElementById('weaponVoteTimer');
const killfeedEl = document.getElementById('killfeed');
const deathcamEl = document.getElementById('deathcam');
const deathcamNameEl = document.getElementById('deathcamName');
const deathcamMetaEl = document.getElementById('deathcamMeta');
const deathcamKillsEl = document.getElementById('deathcamKills');
const deathcamLivesEl = document.getElementById('deathcamLives');
const leaderboardEl = document.getElementById('leaderboard');
const leaderboardRowsEl = document.getElementById('leaderboardRows');
const introEl = document.getElementById('intro');
const introContainer = document.getElementById('container');
const aBg = document.getElementById('a-bg');
const aArc = document.getElementById('a-arc');
const aNum = document.getElementById('a-num');
const aSub = document.getElementById('a-sub');
const aOuter = document.getElementById('a-outer');
const statusEl = document.getElementById('status');
const dotEls = [document.getElementById('d0'), document.getElementById('d1'), document.getElementById('d2')];
let killfeedId = 0;
let introHideTimer = null;
let introStepTimer = null;
let introStepIndex = 0;
let renderedLives = 0;
let visibleLobbyPlayerIds = new Set();
let selectedWeaponVote = null;
let weaponTiebreakTimers = [];
let chamberMenuData = {};
const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Last_bullet_protocol';
const killfeedIcons = window.CHW_KILLFEED_ICONS || {};
const steps = [
  { num:'3',  sub:'READY',  bg:'#1c0000', ring:'#6b0000', arc:'#8B0000', arcW:4,   outer:false, fullArc:false, status:'COMBAT SEQUENCE STARTING', dots:[0]     },
  { num:'2',  sub:'READY',  bg:'#220000', ring:'#880000', arc:'#AA0000', arcW:4.5, outer:false, fullArc:false, status:'STANDBY...',               dots:[1]     },
  { num:'1',  sub:'READY',  bg:'#2a0000', ring:'#AA0000', arc:'#CC0000', arcW:5,   outer:false, fullArc:false, status:'BRACE FOR IMPACT',          dots:[2]     },
  { num:'GO', sub:'ENGAGE', bg:'#380000', ring:'#CC0000', arc:'#FF2222', arcW:6,   outer:true,  fullArc:true,  status:'COMBAT ACTIVE',             dots:[0,1,2] },
];
const defaultIntroDurationMs = 5000;

function postNui(name, data = {}) {
    return fetch(`https://${resourceName}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

function normaliseAssetPath(path) {
    return String(path || '').replace(/^\.?\//, '');
}

function weaponImagePath(option = {}) {
    return normaliseAssetPath(option.image || `img/weapon_${option.type}.png`);
}

function setWeaponImage(image, option = {}) {
    const path = weaponImagePath(option);
    const relativeSrc = path;
    const nuiSrc = `nui://${resourceName}/html/${path}`;
    let triedRelative = false;

    image.src = nuiSrc;
    image.onerror = () => {
        if (!triedRelative) {
            triedRelative = true;
            image.src = relativeSrc;
            return;
        }

        image.classList.add('is-missing');
    };
}

function chamberAction(type, extra = {}) {
    postNui('chamberAction', { type, ...extra });
}

function showChamberMenu(data = {}) {
    const lobbies = Array.isArray(data.lobbies) ? data.lobbies : [];
    chamberMenuData = data;
    chamberCountEl.textContent = lobbies.length;
    chamberStartEl.disabled = data.inQueue === true || data.inMatch === true;
    chamberJoinEl.disabled = data.inQueue === true || data.inMatch === true;
    renderChamberLobbyList(false);
    chamberMenuEl.classList.add('is-collapsed');
    chamberMenuEl.classList.add('is-visible');
    chamberMenuEl.setAttribute('aria-hidden', 'false');
}

function hideChamberMenu() {
    chamberMenuEl.classList.remove('is-visible');
    chamberMenuEl.setAttribute('aria-hidden', 'true');
    renderChamberLobbyList(false);
}

function renderChamberLobbyList(visible) {
    const lobbies = Array.isArray(chamberMenuData.lobbies) ? chamberMenuData.lobbies : [];

    chamberLobbyListEl.replaceChildren();
    chamberLobbyListEl.classList.toggle('is-visible', visible);
    chamberLobbyListEl.setAttribute('aria-hidden', visible ? 'false' : 'true');

    if (!visible) {
        return;
    }

    if (lobbies.length <= 0) {
        const empty = document.createElement('div');
        empty.className = 'chamber-lobby-empty';
        empty.textContent = "Geen actieve lobby's";
        chamberLobbyListEl.appendChild(empty);
        return;
    }

    lobbies.forEach((lobby) => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'chamber-lobby-row';

        const main = document.createElement('span');
        main.className = 'chamber-lobby-name';
        main.textContent = lobby.name || `${lobby.hostName || 'Unknown'}'s Lobby`;

        const meta = document.createElement('span');
        meta.className = 'chamber-lobby-meta';
        meta.textContent = `${Number(lobby.players) || 0}/${Number(lobby.maximumPlayers) || '-'}`;

        row.append(main, meta);
        row.addEventListener('click', () => {
            chamberAction('join', { lobbyId: lobby.id });
        });
        chamberLobbyListEl.appendChild(row);
    });
}

function renderLobby(data = {}) {
    const players = Array.isArray(data.players) ? data.players : [];
    const maxPlayers = Number(data.maximumPlayers) || 0;
    const minimumPlayers = Number(data.minimumPlayers) || 2;
    const countdownSeconds = Number(data.countdownSeconds) || 0;
    const nextLobbyPlayerIds = new Set();

    hideChamberMenu();
    lobbyCountEl.textContent = `${players.length}/${maxPlayers || '-'}`;
    lobbyStatusEl.textContent = data.countdown
        ? `Start over ${countdownSeconds || 0}s`
        : `Waiting for players (${Math.min(players.length, minimumPlayers)}/${minimumPlayers})`;
    lobbyStatusEl.classList.toggle('is-countdown', data.countdown === true);
    lobbyHintEl.textContent = '';
    lobbyHintEl.classList.remove('is-countdown');
    lobbyPlayersEl.replaceChildren();

    const rows = Math.max(maxPlayers, players.length, 1);
    for (let index = 0; index < rows; index += 1) {
        const player = players[index];
        const row = document.createElement('div');
        const playerKey = player ? String(player.id || player.name || index) : '';
        row.className = `lobby-player${player ? '' : ' is-empty'}${player && !visibleLobbyPlayerIds.has(playerKey) ? ' is-new' : ''}`;

        const rank = document.createElement('span');
        rank.className = 'lobby-player-rank';
        rank.textContent = String(index + 1).padStart(2, '0');

        const name = document.createElement('span');
        name.className = 'lobby-player-name';
        name.textContent = player ? player.name : 'Empty slot';

        const tag = document.createElement('span');
        tag.className = 'lobby-player-tag';
        tag.textContent = player && player.host ? 'HOST' : '';

        if (player) {
            nextLobbyPlayerIds.add(playerKey);
        }

        row.append(rank, name, tag);
        lobbyPlayersEl.appendChild(row);
    }

    visibleLobbyPlayerIds = nextLobbyPlayerIds;
    lobbyOverlayEl.classList.add('is-visible');
    lobbyOverlayEl.setAttribute('aria-hidden', 'false');
}

function hideLobby() {
    lobbyOverlayEl.classList.remove('is-visible');
    lobbyOverlayEl.setAttribute('aria-hidden', 'true');
    visibleLobbyPlayerIds = new Set();
}

function showWeaponVote(data = {}) {
    const options = Array.isArray(data.options) ? data.options : [];
    const counts = { ...(data.counts || {}) };
    const players = Array.isArray(data.players) ? data.players : [];
    const serverOwnVote = data.ownVote || null;
    const localVote = selectedWeaponVote || serverOwnVote;
    let totalVotes = players.filter((player) => player.voted).length;

    selectedWeaponVote = localVote;
    weaponVoteEl.classList.remove('is-tiebreak');

    if (localVote && serverOwnVote !== localVote) {
        if (serverOwnVote && counts[serverOwnVote]) {
            counts[serverOwnVote] = Math.max(0, counts[serverOwnVote] - 1);
        } else {
            totalVotes += 1;
        }
        counts[localVote] = (Number(counts[localVote]) || 0) + 1;
    }

    weaponVoteTimerEl.textContent = `${Number(data.seconds) || 0}s`;
    weaponVoteCardsEl.replaceChildren();

    options.forEach((option, index) => {
        const votes = Number(counts[option.type]) || 0;
        const percent = totalVotes > 0 ? Math.round((votes / totalVotes) * 100) : 0;
        const card = document.createElement('button');
        card.type = 'button';
        card.className = `weapon-card${selectedWeaponVote === option.type ? ' is-selected' : ''}`;
        card.dataset.weapon = option.type;

        const rank = document.createElement('span');
        rank.className = 'weapon-card-rank';
        rank.textContent = String(index + 1).padStart(2, '0');

        const title = document.createElement('strong');
        title.className = 'weapon-card-title';
        title.textContent = option.label || option.type || 'Weapon';

        const image = document.createElement('img');
        image.className = 'weapon-card-image';
        image.alt = '';
        setWeaponImage(image, option);

        const meta = document.createElement('span');
        meta.className = 'weapon-card-meta';
        meta.textContent = `${Number(option.ammo) || 0} ammo / knife included`;

        const bar = document.createElement('span');
        bar.className = 'weapon-card-bar';
        bar.style.setProperty('--vote-width', `${percent}%`);

        const count = document.createElement('span');
        count.className = 'weapon-card-count';
        count.textContent = String(votes);

        const scan = document.createElement('span');
        scan.className = 'weapon-card-scan';

        const winnerBurst = document.createElement('span');
        winnerBurst.className = 'weapon-card-winner-burst';

        card.append(scan, winnerBurst, rank, image, title, meta, bar, count);
        card.addEventListener('click', () => {
            selectedWeaponVote = option.type;
            postNui('voteWeapon', { weapon: option.type });
            showWeaponVote(data);
        });

        weaponVoteCardsEl.appendChild(card);
    });

    weaponVoteEl.classList.add('is-visible');
    weaponVoteEl.setAttribute('aria-hidden', 'false');
}

function clearWeaponTiebreakTimers() {
    weaponTiebreakTimers.forEach((timer) => window.clearTimeout(timer));
    weaponTiebreakTimers = [];
}

function centerWeaponFinalists() {
    const movingCards = Array.from(weaponVoteCardsEl.querySelectorAll('.weapon-card:not(.is-eliminated)'));
    const firstPositions = new Map();

    movingCards.forEach((card) => {
        firstPositions.set(card, card.getBoundingClientRect());
    });

    weaponVoteEl.classList.add('is-centered');
    weaponVoteCardsEl.querySelectorAll('.weapon-card.is-eliminated').forEach((card) => card.remove());

    movingCards.forEach((card) => {
        const first = firstPositions.get(card);
        const last = card.getBoundingClientRect();
        const deltaX = first.left - last.left;
        const deltaY = first.top - last.top;

        card.style.transition = 'none';
        card.style.transform = `translate(${deltaX}px, ${deltaY}px)`;

        window.requestAnimationFrame(() => {
            card.style.transition = 'transform 760ms cubic-bezier(0.2, 0.85, 0.2, 1), opacity 240ms ease, box-shadow 240ms ease, border-color 240ms ease';
            card.style.transform = '';
        });
    });
}

function showWeaponTiebreak(data = {}) {
    clearWeaponTiebreakTimers();
    const options = Array.isArray(data.options) ? data.options : [];
    const finalists = Array.isArray(data.finalists) ? data.finalists : [];
    const eliminated = Array.isArray(data.eliminated) ? data.eliminated : [];
    const counts = data.counts || {};
    const winner = data.winner || {};
    const finalistTypes = new Set(finalists.map((option) => option.type));
    const eliminatedTypes = new Set(eliminated.map((option) => option.type));
    const totalVotes = Object.values(counts).reduce((total, value) => total + (Number(value) || 0), 0);

    selectedWeaponVote = null;
    weaponVoteTimerEl.textContent = data.tied ? 'ROLLING' : 'REVEAL';
    weaponVoteCardsEl.style.setProperty('--finalist-count', String(Math.max(1, finalists.length)));
    weaponVoteCardsEl.replaceChildren();
    weaponVoteEl.classList.add('is-visible', 'is-tiebreak');
    weaponVoteEl.classList.remove('is-centered');
    weaponVoteEl.setAttribute('aria-hidden', 'false');

    options.forEach((option, index) => {
        const votes = Number(counts[option.type]) || 0;
        const percent = totalVotes > 0 ? Math.round((votes / totalVotes) * 100) : 0;
        const isFinalist = finalistTypes.has(option.type);
        const card = document.createElement('button');
        card.type = 'button';
        card.disabled = true;
        card.className = [
            'weapon-card',
            isFinalist ? 'is-finalist' : '',
            eliminatedTypes.has(option.type) ? 'is-eliminated' : '',
            isFinalist && index % 2 === 0 ? 'pulse-a' : '',
            isFinalist && index % 2 === 1 ? 'pulse-b' : ''
        ].filter(Boolean).join(' ');
        card.dataset.weapon = option.type;

        const rank = document.createElement('span');
        rank.className = 'weapon-card-rank';
        rank.textContent = String(index + 1).padStart(2, '0');

        const title = document.createElement('strong');
        title.className = 'weapon-card-title';
        title.textContent = option.label || option.type || 'Weapon';

        const image = document.createElement('img');
        image.className = 'weapon-card-image';
        image.alt = '';
        setWeaponImage(image, option);

        const meta = document.createElement('span');
        meta.className = 'weapon-card-meta';
        meta.textContent = isFinalist
            ? data.tied ? 'Random tiebreak' : 'Winner'
            : 'Eliminated';

        const bar = document.createElement('span');
        bar.className = 'weapon-card-bar';
        bar.style.setProperty('--vote-width', `${percent}%`);

        const count = document.createElement('span');
        count.className = 'weapon-card-count';
        count.textContent = String(votes);

        const scan = document.createElement('span');
        scan.className = 'weapon-card-scan';

        const winnerBurst = document.createElement('span');
        winnerBurst.className = 'weapon-card-winner-burst';

        card.append(scan, winnerBurst, rank, image, title, meta, bar, count);
        weaponVoteCardsEl.appendChild(card);
    });

    weaponTiebreakTimers.push(window.setTimeout(() => {
        centerWeaponFinalists();
    }, 1800));

    weaponTiebreakTimers.push(window.setTimeout(() => {
        weaponVoteCardsEl.querySelectorAll('.weapon-card').forEach((card) => {
            const isWinner = card.dataset.weapon === winner.type;
            card.classList.toggle('is-winner', isWinner);
            card.classList.toggle('is-runner-up', !isWinner);
        });
        weaponVoteTimerEl.textContent = 'WINNER';
    }, Math.max(2200, (Number(data.duration) || 5000) - 2200)));
}

function hideWeaponVote() {
    clearWeaponTiebreakTimers();
    weaponVoteEl.classList.remove('is-visible');
    weaponVoteEl.classList.remove('is-tiebreak');
    weaponVoteEl.classList.remove('is-centered');
    weaponVoteEl.setAttribute('aria-hidden', 'true');
    weaponVoteCardsEl.style.removeProperty('--finalist-count');
    selectedWeaponVote = null;
}

function renderLives(lives = 0, maxLives = 3, options = {}) {
    livesEl.replaceChildren();

    for (let i = 1; i <= maxLives; i += 1) {
        const heart = document.createElement('img');
        heart.className = `heart${i > lives ? ' is-empty' : ''}`;
        if (options.animateGain && i > renderedLives && i <= lives) {
            heart.classList.add('is-appearing');
        }
        heart.src = 'img/heart.png';
        heart.alt = '';
        livesEl.appendChild(heart);
    }

    renderedLives = lives;
}

function twoDigitRank(index) {
    return String(index + 1).padStart(2, '0');
}

function renderLeaderboard(rows = [], maxRows = 5) {
    leaderboardRowsEl.replaceChildren();

    rows.slice(0, maxRows).forEach((entry, index) => {
        const row = document.createElement('div');
        row.className = index < 3 ? `leaderboard-row p${index + 1}` : 'leaderboard-row';

        const rank = document.createElement('div');
        rank.className = 'leaderboard-rank';
        rank.textContent = twoDigitRank(index);

        const name = document.createElement('div');
        name.className = 'leaderboard-name';
        name.textContent = entry.name || 'Unknown';

        const kills = document.createElement('div');
        kills.className = 'leaderboard-stat leaderboard-kills';
        kills.textContent = Number(entry.kills) || 0;

        const lives = document.createElement('div');
        lives.className = 'leaderboard-stat leaderboard-life-count';
        lives.textContent = Number(entry.lives) || 0;

        row.append(rank, name, kills, lives);
        leaderboardRowsEl.appendChild(row);
    });

    leaderboardEl.classList.toggle('is-visible', rows.length > 0);
    leaderboardEl.setAttribute('aria-hidden', rows.length > 0 ? 'false' : 'true');
}

function hideLeaderboard() {
    leaderboardEl.classList.remove('is-visible');
    leaderboardEl.setAttribute('aria-hidden', 'true');
    leaderboardRowsEl.replaceChildren();
}

function iconPath(weapon, inlineIcon) {
    if (inlineIcon) {
        return inlineIcon;
    }

    if (killfeedIcons[weapon]) {
        return killfeedIcons[weapon];
    }

    const file = weapon === 'headshot'
        ? 'headshot.png'
        : weapon === 'knife'
            ? 'knife.png'
            : 'pistol.png';

    return `https://cfx-nui-${resourceName}/html/img/${file}`;
}

function relativeIconPath(weapon) {
    if (weapon === 'headshot') {
        return 'img/headshot.png';
    }

    if (weapon === 'knife') {
        return 'img/knife.png';
    }

    return 'img/pistol.png';
}

function nameNode(player, className) {
    const name = document.createElement('span');
    name.className = className;
    name.textContent = player.name || 'Unknown';
    return name;
}

function addKillfeed(entry = {}) {
    const item = document.createElement('div');
    item.className = 'killfeed-item';
    item.dataset.id = String(++killfeedId);

    const distance = document.createElement('div');
    distance.className = 'killfeed-distance';
    distance.textContent = entry.distance ? `${entry.distance}M` : '0M';

    const killer = nameNode(entry.killer || {}, 'killfeed-name killfeed-killer');

    const iconWrap = document.createElement('div');
    iconWrap.className = 'killfeed-icon-wrap';

    const icon = document.createElement('img');
    icon.className = 'killfeed-icon';
    icon.src = iconPath(entry.weapon, entry.icon);
    icon.alt = '';
    icon.onerror = () => {
        if (icon.dataset.fallback !== 'true') {
            icon.dataset.fallback = 'true';
            icon.src = relativeIconPath(entry.weapon);
            return;
        }

        icon.style.display = 'none';
    };
    iconWrap.appendChild(icon);

    const victim = nameNode(entry.victim || {}, 'killfeed-name killfeed-victim');

    item.append(
        distance,
        killer,
        iconWrap,
        victim
    );

    killfeedEl.prepend(item);

    const maxItems = entry.maxItems || 5;
    while (killfeedEl.children.length > maxItems) {
        killfeedEl.lastElementChild.remove();
    }

    window.setTimeout(() => {
        item.remove();
    }, entry.duration || 6000);
}

function clearKillfeed() {
    killfeedEl.replaceChildren();
}

function showDeathcam(data = {}) {
    const killer = data.killer || {};
    deathcamNameEl.textContent = killer.name || 'Unknown';
    deathcamKillsEl.textContent = Number(killer.kills) || 0;
    deathcamLivesEl.textContent = Number(killer.lives) || 0;

    const details = [];
    if (data.distance) {
        details.push(`${data.distance}M`);
    }
    details.push('Spectating killer');
    deathcamMetaEl.textContent = details.join(' / ');

    deathcamEl.classList.add('is-visible');
    deathcamEl.setAttribute('aria-hidden', 'false');
}

function hideDeathcam() {
    deathcamEl.classList.remove('is-visible');
    deathcamEl.setAttribute('aria-hidden', 'true');
}

function clearIntroTimers() {
    if (introStepTimer) {
        window.clearInterval(introStepTimer);
        introStepTimer = null;
    }

    if (introHideTimer) {
        window.clearTimeout(introHideTimer);
        introHideTimer = null;
    }
}

function applyStep(i) {
    const s = steps[i];
    aBg.setAttribute('fill', s.bg);
    aBg.setAttribute('stroke', s.ring);
    aArc.setAttribute('stroke', s.arc);
    aArc.setAttribute('stroke-width', s.arcW);
    aOuter.style.display = s.outer ? '' : 'none';

    if (s.fullArc) {
        aNum.setAttribute('font-size', '62');
        aNum.setAttribute('y', '116');
        aNum.setAttribute('fill', '#FF4444');
        aArc.setAttribute('d', 'M 10,100 A 90,90 0 1 0 190,100');
    } else {
        aNum.setAttribute('font-size', '90');
        aNum.setAttribute('y', '122');
        aNum.setAttribute('fill', s.arc);
        aArc.setAttribute('d', 'M 10,100 A 90,90 0 0 1 190,100');
    }

    aNum.textContent = s.num;
    aSub.textContent = s.sub;
    aSub.setAttribute('fill', s.ring);
    statusEl.textContent = s.status;
    dotEls.forEach((d, idx) => d.classList.toggle('on', s.dots.includes(idx)));
}

function showIntro(duration) {
    const totalDuration = Math.max(1000, Number(duration) || defaultIntroDurationMs);
    const stepDuration = Math.max(400, Math.round(totalDuration / steps.length));

    clearIntroTimers();
    introStepIndex = 0;
    introEl.classList.add('is-visible');
    introContainer.classList.add('visible');
    applyStep(introStepIndex);

    introStepTimer = window.setInterval(() => {
        introStepIndex += 1;
        if (introStepIndex >= steps.length) {
            clearIntroTimers();
            return;
        }
        applyStep(introStepIndex);
    }, stepDuration);

    introHideTimer = window.setTimeout(hideIntro, totalDuration);
}

function hideIntro() {
    clearIntroTimers();
    introEl.classList.remove('is-visible');
    introContainer.classList.remove('visible');
}

document.querySelector('[data-chamber-toggle]').addEventListener('click', () => {
    chamberMenuEl.classList.toggle('is-collapsed');
});

chamberStartEl.addEventListener('click', () => {
    chamberAction('start');
});

chamberJoinEl.addEventListener('click', () => {
    renderChamberLobbyList(!chamberLobbyListEl.classList.contains('is-visible'));
});

chamberCloseEl.addEventListener('click', () => {
    postNui('closeChamberMenu');
});

lobbyLeaveEl.addEventListener('click', () => {
    chamberAction('leave');
    hideLobby();
    postNui('closeChamberMenu');
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') {
        return;
    }

    if (lobbyOverlayEl.classList.contains('is-visible')) {
        return;
    }

    if (weaponVoteEl.classList.contains('is-visible')) {
        return;
    }

    hideChamberMenu();
    hideLobby();
    postNui('closeChamberMenu');
});

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'showChamberMenu') {
        showChamberMenu(data.data || {});
        return;
    }

    if (data.action === 'hideChamberMenu') {
        hideChamberMenu();
        return;
    }

    if (data.action === 'showLobby') {
        renderLobby(data.data || {});
        return;
    }

    if (data.action === 'hideLobby') {
        hideLobby();
        return;
    }

    if (data.action === 'showWeaponVote') {
        showWeaponVote(data.data || {});
        return;
    }

    if (data.action === 'showWeaponTiebreak') {
        showWeaponTiebreak(data.data || {});
        return;
    }

    if (data.action === 'hideWeaponVote') {
        hideWeaponVote();
        return;
    }

    if (data.action === 'showLives') {
        renderLives(data.lives, data.maxLives);
        livesEl.classList.add('is-visible');
        return;
    }

    if (data.action === 'updateLives') {
        renderLives(data.lives, data.maxLives, { animateGain: data.gainedLife === true });
        return;
    }

    if (data.action === 'hideLives') {
        livesEl.classList.remove('is-visible');
        renderLives(0, data.maxLives || 3);
        renderedLives = 0;
        return;
    }

    if (data.action === 'killfeed') {
        addKillfeed(data.data);
        return;
    }

    if (data.action === 'clearKillfeed') {
        clearKillfeed();
        return;
    }

    if (data.action === 'showDeathcam') {
        showDeathcam(data.data || {});
        return;
    }

    if (data.action === 'hideDeathcam') {
        hideDeathcam();
        return;
    }

    if (data.action === 'leaderboard') {
        renderLeaderboard(data.rows || [], data.maxRows || 5);
        return;
    }

    if (data.action === 'hideLeaderboard') {
        hideLeaderboard();
        return;
    }

    if (data.action === 'showIntro') {
        showIntro(data.duration);
        return;
    }

    if (data.action === 'hideIntro') {
        hideIntro();
    }
});
