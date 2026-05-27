const jwt = require('jsonwebtoken');

function socketAuthMiddleware(socket, next) {
  // Client must send JWT in the auth handshake object:
  // socket = io('http://...', { auth: { token: 'Bearer <jwt>' } })
  const authHeader = socket.handshake.auth?.token;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new Error('AUTHENTICATION_REQUIRED: No token provided on socket handshake.'));
  }

  const token = authHeader.split(' ')[1];

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET_KEY || 'passwordKey');
    socket.user = decoded; // Attach user data to socket for use in handlers
    next();
  } catch (err) {
    next(new Error('AUTHENTICATION_FAILED: Token is invalid or expired.'));
  }
}

module.exports = socketAuthMiddleware;
