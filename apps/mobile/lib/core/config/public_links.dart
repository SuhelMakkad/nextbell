/// Beta builds use their own deployed public policies, configured with the API.
const _publicOrigin = String.fromEnvironment(
  'NEXTBELL_API_ORIGIN',
  defaultValue: 'https://www.nextbell.org',
);
const nextbellWebsiteLinks = <String, String>{
  'Privacy policy': '$_publicOrigin/privacy',
  'Help & support': '$_publicOrigin/support',
  'Terms of use': '$_publicOrigin/terms',
  'Remove your data': '$_publicOrigin/data-deletion',
};
