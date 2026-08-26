const express = require('express');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const device = await hdhr.getDeviceInfo();
    res.render('index', { device, error: null, host: hdhr.HOST });
  } catch (err) {
    res.render('index', { device: null, error: err.message, host: hdhr.HOST });
  }
});

module.exports = router;
