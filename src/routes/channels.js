const express = require('express');
const hdhr = require('../hdhomerun');

const router = express.Router();

router.get('/channels', async (req, res) => {
  try {
    const channels = await hdhr.getLineup();
    res.render('channels', { channels: channels || [], error: null });
  } catch (err) {
    res.render('channels', { channels: [], error: err.message });
  }
});

module.exports = router;
