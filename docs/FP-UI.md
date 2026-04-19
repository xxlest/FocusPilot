<!--
 * @Author: xxl
 * @Date: 2026-04-16 10:49:11
 * @LastEditors: xxl
 * @LastEditTime: 2026-04-16 16:20:57
 * @Description:
 * @FilePath: /FocusPilot/docs/FP-UI.md
-->

prd的功能布局需要优化一下，功能整合需要参考整合到新品的能力中 ，FocusPilot主要架构会以当前swift作为前端，技术架构层面会整合Multica（裁剪后个
人版，去除分配issue给指定用户，仅支持单用户）的后端，功能层面主要方向 整合Multica的agent和runtime的配置能力，zcode的workspace的session运行模式，以及plane的项目管理方式：
目前FocusPilot功能（0.0.1):侧边栏功能改为Notifications、workspace、projects、AICrew、settings

# Notifications页面

包含

- Notifications提供任务执行完成的列表和通知，tab支持红色未读消息数字,顶部提供横向图标 Tab 条按all，project来切换展示，参考mutical的inbox页面
- 工作项work iterm

## workspace页面

FP workspace的主要功能包括：Home、serach,kanban、inbox收集箱(灵感和to-read待阅读和临时工作项任务的管理)、settings其中

- search搜索功能，提供搜索框，支持全局的搜索，包括项目，工作项的搜索和定位
- home页面提供AI对话框和最近的操作记录以及，这个对话框会选择AICrew的配置指定的Agent，主要起到整个AIOS的唯一入口，后续移动端的的对话接入界面入口，实现项目和待办事项所有的对话内容
- kanban页面提供任务的配置和执行和整个状态的管理， 参考Multica的的issue创建分配给agent执行，系统会定时自动调度执行，看板提供backlog,todo,in progresss,in review,done和blaocked,同时todo提供today week,month,还有季度的规划，点击进入可以跳转到详情和甘特图的排期
- inbox收集箱页面提供灵感（参考palne的stickies）和to-read待阅读和临时任务的管理
- settings页面提供配置功能，包括AICrew的配置、workspace的配置、projects的配置、settings的配置等
  projects包括：project的文件预览，同时中间常驻的是session对话框

  1.主要方向是整合和参考Multica的agent和runtime的配置能力以及issue自动执行的方式，agent和runtime的整合到到settings模块

  2.整合

## projects页面

## AICrew页面

## settings页面
