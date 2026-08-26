const express = require('express');
const path = require('path');

const hdhr = require('./src/hdhomerun');
const indexRoutes = require('./src/routes/index');
const channelsRoutes = require('./src/routes/channels');
const scanRoutes = require('./src/routes/scan');
const statusRoutes = require('./src/routes/status');

const app = express();
const PORT = process.env.PORT || 8080;

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static(path.join(__dirname, 'public')));

app.locals.deviceSystemLogUrl = `http://${hdhr.HOST}/log.html`;

app.use(indexRoutes);
app.use(channelsRoutes);
app.use(scanRoutes);
app.use(statusRoutes);

app.listen(PORT, () => {
  console.log(`hdhomerun-web listening on port ${PORT}`);
});
