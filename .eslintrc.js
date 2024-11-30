const OFF = 'off'

module.exports = {
  extends: require.resolve('@ostai/eslint-config'),
  rules: {
    'prefer-object-spread': OFF,
    'import/no-unresolved': OFF
  }
}
