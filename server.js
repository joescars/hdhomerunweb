const express = require('express');
const path = require('path');
const compression = require('compression');

const hdhr = require('./src/hdhomerun');
const requestTiming = require('./src/middleware/requestTiming');
const indexRoutes = require('./src/routes/index');
const channelsRoutes = require('./src/routes/channels');
const scanRoutes = require('./src/routes/scan');
const statusRoutes = require('./src/routes/status');
const guideRoutes = require('./src/routes/guide');
const watchRoutes = require('./src/routes/watch');
const recordingsRoutes = require('./src/routes/recordings');
const apiRoutes = require('./src/routes/api');

const app = express();
const PORT = process.env.PORT || 8080;
const ASSET_VERSION = process.env.ASSET_VERSION || Date.now().toString();

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(requestTiming);
app.use(compression());
app.use(express.static(path.join(__dirname, 'public'), {
  maxAge: '7d',
  etag: true,
  lastModified: true,
  immutable: true,
}));
app.use(express.urlencoded({ extended: false }));

app.locals.deviceSystemLogUrl = `http://${hdhr.HOST}/log.html`;
app.locals.assetVersion = ASSET_VERSION;

// The mobile guide (guideRoutes) is the primary client experience, mounted
// at the root. Device-setup/management pages live under /admin - they're
// not gone, just no longer the front door (see CHANGELOG for the LunaTV
// mobile client redesign).
app.use('/admin', indexRoutes);
app.use('/admin', channelsRoutes);
app.use('/admin', scanRoutes);
app.use('/admin', statusRoutes);
app.use(guideRoutes);
app.use(watchRoutes);
app.use(recordingsRoutes);
app.use(apiRoutes);

const server = app.listen(PORT, () => {
  console.log(`hdhomerun-web listening on port ${PORT}`);
});

server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;
