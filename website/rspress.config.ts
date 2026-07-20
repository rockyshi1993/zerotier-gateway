import * as path from 'node:path';
import { defineConfig } from '@rspress/core';

const userSidebar = [
  {
    text: '开始使用',
    items: [
      { text: '文档首页', link: '/' },
      { text: '5 分钟快速开始', link: '/quick-start' },
      { text: '安装与互访验证', link: '/verification' },
      { text: '安装总览', link: '/install' },
      { text: '安全升级', link: '/upgrade' }
    ]
  },
  {
    text: '设备配置',
    items: [
      { text: 'Ubuntu 节点', link: '/ubuntu' },
      { text: 'Windows 客户端', link: '/windows' }
    ]
  },
  {
    text: '常用任务',
    items: [
      { text: '远程访问', link: '/remote' },
      { text: '代理上网', link: '/proxy' },
      { text: '手机私有 Exit Node', link: '/exit-node' },
      { text: '公网代理', link: '/proxy-public' },
      { text: '多台代理服务器', link: '/proxy-multi-server' },
      { text: '代理排除规则', link: '/proxy-rules' },
      { text: '按客户端限速', link: '/rate-limit' },
      { text: '公网站点发布', link: '/publish-site' }
    ]
  },
  {
    text: '进阶与恢复',
    items: [
      { text: '中转兜底', link: '/relay' },
      { text: '故障排查', link: '/troubleshooting' },
      { text: '安全说明', link: '/security' },
      { text: '回滚与卸载', link: '/rollback' }
    ]
  }
];

export default defineConfig({
  root: path.join(__dirname, '..', 'docs'),
  outDir: 'dist',
  base: '/zerotier-gateway/',
  lang: 'zh',
  title: 'ZeroTier Gateway',
  description: '通过脚本搭建 ZeroTier 私有远程访问、HTTP/SOCKS5 代理与可选中转。',
  icon: '/favicon.svg',
  head: [['script', { src: './site-accessibility.js', defer: '' }]],
  globalStyles: path.join(__dirname, 'styles', 'index.css'),
  markdown: {
    link: {
      checkDeadLinks: false
    }
  },
  search: {
    codeBlocks: true
  },
  themeConfig: {
    localeRedirect: 'never',
    nav: [
      { text: '开始使用', link: '/quick-start' },
      { text: '验证', link: '/verification' },
      { text: '远程访问', link: '/remote' },
      { text: '代理上网', link: '/proxy' },
      { text: '手机 Exit Node', link: '/exit-node' },
      { text: '公网站点', link: '/publish-site' },
      { text: '故障排查', link: '/troubleshooting' },
      { text: '维护者', link: '/release' }
    ],
    sidebar: {
      '/': userSidebar
    },
    socialLinks: [
      {
        icon: 'github',
        mode: 'link',
        content: 'https://github.com/rockyshi1993/zerotier-gateway'
      }
    ],
    footer: {
      message: 'ZeroTier Gateway · MIT License'
    }
  }
});
