import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'FHEVM Bootcamp',
  description: 'Zero to Mainnet — A 4-week bootcamp for building confidential smart contracts with Zama FHEVM and Foundry',

  // Set base for GitHub Pages — update if repo name changes
  base: '/fhevm-bootcamp/',

  head: [
    ['meta', { name: 'theme-color', content: '#6d28d9' }],
    ['meta', { property: 'og:title', content: 'FHEVM Bootcamp: Zero to Mainnet' }],
    ['meta', { property: 'og:description', content: 'The first Foundry-based FHEVM bootcamp. 4 weeks from FHE theory to mainnet deployment.' }],
  ],

  themeConfig: {
    siteTitle: 'FHEVM Bootcamp',

    nav: [
      { text: 'Home', link: '/' },
      { text: 'Getting Started', link: '/getting-started' },
      {
        text: 'Curriculum',
        items: [
          { text: 'Week 1: Foundations', link: '/week-1/' },
          { text: 'Week 2: Access Control', link: '/week-2/' },
          { text: 'Week 3: Confidential DeFi', link: '/week-3/' },
          { text: 'Week 4: Capstone', link: '/week-4/' },
        ]
      },
      { text: 'Resources', link: '/resources/cheatsheet' },
    ],

    sidebar: {
      '/week-1/': [
        {
          text: 'Week 1: Foundations & First Contract',
          items: [
            { text: 'Overview & Milestones', link: '/week-1/' },
            { text: 'Lesson 1: FHE Theory', link: '/week-1/lesson-1-fhe-theory' },
            { text: 'Lesson 2: Environment Setup', link: '/week-1/lesson-2-setup' },
            { text: 'Lesson 3: Hello FHE', link: '/week-1/lesson-3-hello-fhe' },
            { text: 'Homework: EncryptedPoll', link: '/week-1/homework' },
            { text: 'Instructor Notes', link: '/week-1/instructor' },
          ]
        }
      ],
      '/week-2/': [
        {
          text: 'Week 2: Encrypted State & Access Control',
          items: [
            { text: 'Overview & Milestones', link: '/week-2/' },
            { text: 'Lesson 1: Access Control', link: '/week-2/lesson-1-access-control' },
            { text: 'Lesson 2: FHE Patterns', link: '/week-2/lesson-2-patterns' },
            { text: 'Homework: EncryptedTipJar', link: '/week-2/homework' },
            { text: 'Instructor Notes', link: '/week-2/instructor' },
          ]
        }
      ],
      '/week-3/': [
        {
          text: 'Week 3: Confidential DeFi',
          items: [
            { text: 'Overview & Milestones', link: '/week-3/' },
            { text: 'Lesson 1: Confidential Token', link: '/week-3/lesson-1-token' },
            { text: 'Lesson 2: Advanced Patterns', link: '/week-3/lesson-2-advanced' },
            { text: 'Homework: Extended ERC20', link: '/week-3/homework' },
            { text: 'Instructor Notes', link: '/week-3/instructor' },
          ]
        }
      ],
      '/week-4/': [
        {
          text: 'Week 4: Capstone & Production',
          items: [
            { text: 'Overview & Milestones', link: '/week-4/' },
            { text: 'Lesson 1: Sealed Auction', link: '/week-4/lesson-1-auction' },
            { text: 'Lesson 2: Deployment', link: '/week-4/lesson-2-deployment' },
            { text: 'Capstone: Vickrey Auction', link: '/week-4/homework' },
            { text: 'Instructor Notes', link: '/week-4/instructor' },
          ]
        }
      ],
      '/resources/': [
        {
          text: 'Resources',
          items: [
            { text: 'FHE Cheat Sheet', link: '/resources/cheatsheet' },
            { text: 'Glossary', link: '/resources/glossary' },
            { text: 'Hardhat Migration Guide', link: '/resources/migration' },
          ]
        }
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/0xNana/fhevm-bootcamp' }
    ],

    search: {
      provider: 'local'
    },

    footer: {
      message: 'Built for the Zama Developer Program — Bounty Track',
      copyright: 'MIT License'
    },

    editLink: {
      pattern: 'https://github.com/0xNana/fhevm-bootcamp/edit/main/website/:path',
      text: 'Edit this page on GitHub'
    },

    outline: {
      level: [2, 3]
    }
  }
})
