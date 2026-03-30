// Immediately complete the level on text levels
const level_loaded = (level) => {
  complete_level(level['id'], level['name'], level['next']);
};
