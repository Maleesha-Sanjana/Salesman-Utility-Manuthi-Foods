app.post('/api/auth/logout-all-salesmans', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ success: false, message: 'Database not connected' });
    }

    await pool.request()
      .query('UPDATE gen_salesman SET isLogged = 0 WHERE isAdmin = 0 AND isSuper = 0');
      
    console.log(`🚪 All salesmans logged out successfully by admin`);
    res.json({ success: true, message: 'All salesmans logged out successfully' });
  } catch (err) {
    console.error('Error logging out all salesmans:', err);
    res.status(500).json({ success: false, message: 'Logout all salesmans failed', error: err.message });
  }
});
