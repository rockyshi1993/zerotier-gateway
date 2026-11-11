import * as path from 'node:path';
import { defineConfig } from '@rspress/core';

const userSidebar = [
  {
    text: '开始使用',
    items: [
      { text: '环境与路径选择', link: '/install' },
      { text: '部署私有网关', link: '/quick-start' },
      { text: '安装与功能验收', link: '/verification' }
    ]
  },
  {
    text: '功能指南',
    items: [
      { text: '仅设备互访（无需网关）', link: '/remote' },
      { text: '私有 HTTP/SOCKS5 代理', link: '/proxy' },
      { text: 'Android IPv4 Exit Node', link: '/exit-node' },
      { text: '指定 TCP 中转', link: '/relay' },
      { text: '公网站点发布', link: '/publish-site' }
    ]
  },
  {
    text: '高级配置',
    items: [
      { text: '公网代理（高风险）', link: '/proxy-public' },
      { text: '多代理节点池', link: '/proxy-multi-server' },
      { text: 'PAC / 本地分流规则', link: '/proxy-rules' },
      { text: '按客户端代理限速', link: '/rate-limit' }
    ]
  },
  {
    text: '运维与排障',
    items: [
      { text: 'Ubuntu 节点', link: '/ubuntu' },
      { text: 'Windows 客户端', link: '/windows' },
      { text: '故障排查', link: '/troubleshooting' },
      { text: '安全边界', link: '/security' },
      { text: '安全升级', link: '/upgrade' },
      { text: '停用、回滚与卸载', link: '/rollback' }
    ]
  }
];

export default defineConfig({
  root: path.join(__dirname, '..', 'docs'),
  outDir: 'dist',
  base: '/zerotier-gateway/',
  lang: 'zh',
  title: 'ZeroTier Gateway',
  description: '为 ZeroTier 私有网络按需部署自托管代理、IPv4 Exit Node、指定 TCP 中转和内网服务发布。',
  icon: '/favicon.svg',
  // Absolute URL scoped to the GitHub Pages base: nested routes must not resolve it relatively.
  head: ['<script src="/zerotier-gateway/site-accessibility.js" defer></script>'],
  globalStyles: path.join(__dirname, 'styles', 'index.css'),
  markdown: {
    link: { checkDeadLinks: false }
  },
  search: { codeBlocks: true },
  themeConfig: {
    localeRedirect: 'never',
    nav: [
      { text: '开始使用', link: '/quick-start' },
      { text: '功能指南', link: '/proxy' },
      { text: 'Android Exit Node', link: '/exit-node' },
      { text: '验收', link: '/verification' },
      { text: '故障排查', link: '/troubleshooting' }
    ],
    sidebar: { '/': userSidebar },
    socialLinks: [{
      icon: 'github',
      mode: 'link',
      content: 'https://github.com/rockyshi1993/zerotier-gateway'
    }],
    footer: { message: 'ZeroTier Gateway · MIT License · 文档对应当前 main 开发源码' }
  }
});
