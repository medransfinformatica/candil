// CORS / Cross-Origin-Resource-Policy para Node.js / Express
// Uso:
//   const corsHeaders = require('./cors-middleware');
//   app.use(corsHeaders);
module.exports = function corsHeaders(req, res, next) {
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', '*');
  res.setHeader('Access-Control-Expose-Headers', '*');
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    return res.end();
  }
  next();
};
