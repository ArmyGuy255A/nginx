const gameBoard = document.getElementById('gameBoard');
const gameStatus = document.getElementById('gameStatus');
let board = ['', '', '', '', '', '', '', '', ''];
let currentPlayer = 'X';
let gameActive = true;

// Winning combinations
const winningCombinations = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6]
];

function handleCellClick(e) {
    const cell = e.target;
    const index = cell.getAttribute('data-index');

    // Ignore clicks on already filled cells or if the game is over
    if (board[index] !== '' || !gameActive || currentPlayer === 'O') return;

    // Human player moves
    makeMove(index, 'X');

    if (!gameActive) return;

    // AI player (O) takes a random move after a slight delay
    setTimeout(() => {
        if (gameActive) {
            const aiMove = getRandomMove();
            if (aiMove !== -1) makeMove(aiMove, 'O');
        }
    }, 500);
}

function makeMove(index, player) {
    board[index] = player;
    const cell = gameBoard.querySelector(`[data-index="${index}"]`);
    cell.classList.add(player.toLowerCase());
    cell.textContent = player;

    if (checkWin()) {
        gameStatus.textContent = `Player ${player} wins!`;
        gameActive = false;
        return;
    }

    if (board.every(cell => cell !== '')) {
        gameStatus.textContent = "It's a draw!";
        gameActive = false;
        return;
    }

    currentPlayer = currentPlayer === 'X' ? 'O' : 'X';
    gameStatus.textContent = `Player ${currentPlayer}'s turn`;
}

function getRandomMove() {
    const availableMoves = board
        .map((cell, index) => (cell === '' ? index : null))
        .filter(index => index !== null);

    if (availableMoves.length === 0) return -1;

    const randomIndex = Math.floor(Math.random() * availableMoves.length);
    return availableMoves[randomIndex];
}

function checkWin() {
    return winningCombinations.some(combination => {
        return combination.every(index => board[index] === currentPlayer);
    });
}

function resetGame() {
    board = ['', '', '', '', '', '', '', '', ''];
    currentPlayer = 'X';
    gameActive = true;
    gameStatus.textContent = "Player X's turn";

    document.querySelectorAll('.cell').forEach(cell => {
        cell.textContent = '';
        cell.classList.remove('x', 'o');
    });
}

gameBoard.addEventListener('click', handleCellClick);
