(function () {
    const panel = document.getElementById('faction-panel');
    const tabContent = document.getElementById('tab-content');
    const tabs = document.getElementById('tabs');
    const btnClose = document.getElementById('btn-close');
    const adminCreateFactionContainer = document.getElementById('admin-create-faction-container');
    const btnCreateFactionStatic = document.getElementById('btn-create-faction-static');
    
    let currentFaction = null;
    let currentTab = 'overview';
    let isAdminMode = false;
    let isPhoneMode = false;
    let phoneClockInterval = null;
    const phoneWrapper = document.getElementById('phone-wrapper');
    const phoneScreen = document.getElementById('phone-screen');
    const phoneClock = document.getElementById('phone-clock');
    let tabData = {
        members: null,
        weapons: null,
        conflicts: null,
        cooldowns: null,
        warnings: null,
        territory: null
    };
    
    function updateTabsForRole(admin) {
        isAdminMode = admin;
        const tabsContainer = document.getElementById('tabs');
        
        if (admin) {
            // Admin tabs
            tabsContainer.innerHTML = `
                <button class="tab-btn active" data-tab="overview">Overview</button>
                <button class="tab-btn" data-tab="conflicts">Conflicts</button>
                <button class="tab-btn" data-tab="weapons">Weapon Registration</button>
                <button class="tab-btn" data-tab="cooldowns">Cooldowns</button>
                <button class="tab-btn" data-tab="violations">Violations</button>
                <button class="tab-btn" data-tab="factions">Factions</button>
                <button class="tab-btn" data-tab="reports">Reports</button>
                <button class="tab-btn" data-tab="ck">CK Requests</button>
                <button class="tab-btn" data-tab="territory">Territory</button>
                <button class="tab-btn" data-tab="rules">Rules</button>
            `;
            document.getElementById('panel-title').textContent = 'Faction Management Admin';
            document.getElementById('panel-subtitle').textContent = 'Manage all factions and settings';
        } else {
            // Member tabs
            tabsContainer.innerHTML = `
                <button class="tab-btn active" data-tab="overview">Overview</button>
                <button class="tab-btn" data-tab="report">Report</button>
                <button class="tab-btn" data-tab="members">Members</button>
                <button class="tab-btn" data-tab="ck">CK Request</button>
                <button class="tab-btn" data-tab="territory">Territory</button>
                <button class="tab-btn" data-tab="reputation">Reputation</button>
                <button class="tab-btn" data-tab="conflicts">Conflicts</button>
                <button class="tab-btn" data-tab="cooldowns">Cooldowns</button>
                <button class="tab-btn" data-tab="weapons">Weapons</button>
                <button class="tab-btn" data-tab="warnings">Warnings</button>
                <button class="tab-btn" data-tab="rules">Rules</button>
            `;
            document.getElementById('panel-title').textContent = 'Faction Panel';
            document.getElementById('panel-subtitle').textContent = 'Manage your faction';
        }
        
        // Show/hide static create faction button based on admin mode
        updateCreateFactionButtonVisibility();
        
        // Re-attach event listeners
        tabsContainer.addEventListener('click', function(e) {
            if (e.target.classList.contains('tab-btn')) {
                const tabName = e.target.getAttribute('data-tab');
                if (tabName) {
                    switchTab(tabName);
                }
            }
        });
    }
    
    function updateCreateFactionButtonVisibility() {
        if (adminCreateFactionContainer && btnCreateFactionStatic) {
            // Show button only in admin mode and on overview tab
            if (isAdminMode && currentTab === 'overview') {
                adminCreateFactionContainer.classList.remove('hidden');
            } else {
                adminCreateFactionContainer.classList.add('hidden');
            }
        }
    }

    function isNui() {
        return typeof window.GetParentResourceName === 'function' && window.GetParentResourceName() !== '';
    }

    function post(name, data) {
        if (!isNui()) return;
        fetch(`https://${window.GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    function postWithData(name, data) {
        if (!isNui()) return Promise.resolve(null);
        return fetch(`https://${window.GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then(r => r.json()).catch(() => null);
    }

    function clearCooldownTimers() {
        if (window.cooldownIntervals && window.cooldownIntervals.length) {
            window.cooldownIntervals.forEach(function(id) { clearInterval(id); });
            window.cooldownIntervals = [];
        }
    }

    function updatePhoneClock() {
        if (!phoneClock) return;
        const now = new Date();
        const h = String(now.getHours()).padStart(2, '0');
        const m = String(now.getMinutes()).padStart(2, '0');
        phoneClock.textContent = h + ':' + m;
    }

    function openPhoneMode() {
        if (!phoneWrapper || !phoneScreen) return;
        isPhoneMode = true;
        if (panel.parentElement !== phoneScreen) phoneScreen.appendChild(panel);
        panel.classList.add('phone-mode');
        phoneWrapper.classList.remove('hidden');
        phoneWrapper.classList.add('active');
        updatePhoneClock();
        if (phoneClockInterval) clearInterval(phoneClockInterval);
        phoneClockInterval = setInterval(updatePhoneClock, 1000);
    }

    function exitPhoneMode() {
        if (!phoneWrapper) return;
        isPhoneMode = false;
        phoneWrapper.classList.add('hidden');
        phoneWrapper.classList.remove('active');
        if (phoneClockInterval) { clearInterval(phoneClockInterval); phoneClockInterval = null; }
        panel.classList.remove('phone-mode');
        if (panel.parentElement !== document.body) document.body.appendChild(panel);
    }

    function close() {
        clearCooldownTimers();
        panel.classList.add('hidden');
        if (isPhoneMode) exitPhoneMode();
        currentFaction = null;
        currentTab = 'overview';
        tabContent.innerHTML = '';
        if (isNui()) post('close');
    }

    function switchTab(tabName) {
        if (currentTab === 'cooldowns') clearCooldownTimers();
        currentTab = tabName;

        // Update active tab button
        tabs.querySelectorAll('.tab-btn').forEach(btn => {
            btn.classList.remove('active');
            if (btn.getAttribute('data-tab') === tabName) {
                btn.classList.add('active');
            }
        });
        
        // Update create faction button visibility
        updateCreateFactionButtonVisibility();
        
        // Load tab content
        loadTabContent(tabName);
    }

    function loadTabContent(tabName) {
        // For admin overview, use static button - just show loading for content
        if (tabName === 'overview' && isAdminMode) {
            // Static button is in HTML, just show loading for factions list
            tabContent.innerHTML = '<div class="overview-content"><div class="info-card" style="margin-bottom: 20px;"><h3 style="margin-bottom: 16px; color: #fff; font-size: 1.125rem; font-weight: 600;">All Registered Factions</h3><div class="empty-state"><span class="empty-text">Loading...</span></div></div></div>';
        } else {
            // Show loading state for non-overview tabs or non-admin
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
        }
        
        // Request data from client for this tab
        if (isNui()) {
            post('requestTabData', { tab: tabName, isAdmin: isAdminMode });
        } else {
            // For testing without NUI
            if (tabName === 'overview') {
                renderOverview();
            }
        }
    }

    function renderOverview() {
        if (!currentFaction) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No faction data</span></div>';
            return;
        }
        
        const f = currentFaction;
        tabContent.innerHTML = `
            <div class="overview-content">
                <div class="info-card">
                    <h3>${escapeHtml(f.label || f.name || 'Faction')}</h3>
                    <div class="info-row">
                        <span class="info-label">Type:</span>
                        <span class="info-value">${escapeHtml(f.type || 'Unknown')}</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Reputation:</span>
                        <span class="info-value">${f.reputation || 0}</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Active Wars:</span>
                        <span class="info-value">${f.active_wars || 0} / ${f.max_wars || 0}</span>
                    </div>
                </div>
            </div>
        `;
    }

    function renderList(items, emptyText) {
        if (!items || items.length === 0) {
            tabContent.innerHTML = `<div class="empty-state"><span class="empty-text">${emptyText}</span></div>`;
            return;
        }
        
        tabContent.innerHTML = '<div class="list-container">' + items.map(item => {
            return `<div class="list-item">${item}</div>`;
        }).join('') + '</div>';
    }
    
    function renderMembersList(members, isAdmin, factionId, showInviteButton) {
        if (!members || members.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No members found</span></div>';
            return;
        }
        
        var factionData = currentFaction && (currentFaction.faction || currentFaction);
        showInviteButton = showInviteButton && factionId && factionData;
        const factionForInvite = showInviteButton ? { id: factionId, label: (factionData.label || 'Faction'), name: (factionData.name || '') } : null;
        
        let html = '<div class="members-list">';
        if (showInviteButton) {
            html += `
                <div class="members-list-header">
                    <span class="members-list-title">Members</span>
                    <button type="button" class="btn-action-small btn-invite-icon" id="members-invite-btn" title="Invite Member">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                            <circle cx="8.5" cy="7" r="4"></circle>
                            <line x1="20" y1="8" x2="20" y2="14"></line>
                            <line x1="23" y1="11" x2="17" y2="11"></line>
                        </svg>
                    </button>
                </div>
            `;
        }
        html += '<div class="members-list-items">';
        members.forEach(member => {
            const initials = (member.player_name || 'U').split(' ').map(n => n.charAt(0)).join('').toUpperCase().substring(0, 2);
            const nameHash = (member.player_name || '').split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
            const hue = (nameHash * 7) % 360;
            const color = `hsl(${hue}, 65%, 50%)`;
            const rankLabel = getRankLabel(member.rank);
            
            html += `
                <div class="member-item" data-member-id="${member.id}" data-identifier="${escapeHtml(member.identifier || '')}">
                    <div style="display: flex; align-items: center; gap: 14px; flex: 1;">
                        <div class="player-icon-small" style="background: ${color};">
                            ${escapeHtml(initials)}
                        </div>
                        <div style="flex: 1;">
                            <div class="player-name">${escapeHtml(member.player_name || 'Unknown')}</div>
                            <div style="color: #71717a; font-size: 12px; margin-top: 2px;">
                                ${escapeHtml(rankLabel)} • Rep: ${member.reputation_contribution || 0}
                            </div>
                        </div>
                    </div>
                    ${isAdmin ? `
                        <div class="member-actions">
                            <button class="btn-action-small btn-set-rank" data-member-id="${member.id}" data-identifier="${escapeHtml(member.identifier || '')}" data-current-rank="${member.rank}" title="Set Rank">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <path d="M12 2L2 7l10 5 10-5-10-5z"></path>
                                    <path d="M2 17l10 5 10-5"></path>
                                    <path d="M2 12l10 5 10-5"></path>
                                </svg>
                            </button>
                            <button class="btn-action-small btn-warning" data-member-id="${member.id}" data-identifier="${escapeHtml(member.identifier || '')}" data-member-name="${escapeHtml(member.player_name || 'Unknown')}" title="Add Warning">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"></path>
                                    <line x1="12" y1="9" x2="12" y2="13"></line>
                                    <line x1="12" y1="17" x2="12.01" y2="17"></line>
                                </svg>
                            </button>
                            <button class="btn-action-small btn-kick" data-member-id="${member.id}" data-identifier="${escapeHtml(member.identifier || '')}" data-member-name="${escapeHtml(member.player_name || 'Unknown')}" title="Kick Member">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <path d="M18 6L6 18M6 6l12 12"></path>
                                </svg>
                            </button>
                            ${member.rank !== 'boss' ? `
                                <button class="btn-action-small btn-transfer" data-member-id="${member.id}" data-identifier="${escapeHtml(member.identifier || '')}" data-member-name="${escapeHtml(member.player_name || 'Unknown')}" title="Transfer Boss">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                                        <circle cx="9" cy="7" r="4"></circle>
                                        <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
                                        <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
                                    </svg>
                                </button>
                            ` : ''}
                        </div>
                    ` : ''}
                </div>
            `;
        });
        html += '</div></div>';
        tabContent.innerHTML = html;
        
        if (showInviteButton && factionForInvite) {
            const inviteBtn = document.getElementById('members-invite-btn');
            if (inviteBtn) {
                inviteBtn.addEventListener('click', function() {
                    showInviteMemberDialog(factionForInvite);
                });
            }
        }
        
        // Attach event listeners for member actions
        if (isAdmin) {
            tabContent.querySelectorAll('.btn-set-rank').forEach(btn => {
                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const memberId = this.getAttribute('data-member-id');
                    const identifier = this.getAttribute('data-identifier');
                    const currentRank = this.getAttribute('data-current-rank');
                    showSetRankDialog(memberId, identifier, currentRank, factionId);
                });
            });
            
            tabContent.querySelectorAll('.btn-warning').forEach(btn => {
                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const memberId = this.getAttribute('data-member-id');
                    const memberName = this.getAttribute('data-member-name');
                    showAddWarningDialog(memberId, memberName, factionId);
                });
            });
            
            tabContent.querySelectorAll('.btn-kick').forEach(btn => {
                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const memberId = this.getAttribute('data-member-id');
                    const identifier = this.getAttribute('data-identifier');
                    const memberName = this.getAttribute('data-member-name');
                    post('requestKickConfirm', {
                        factionId: factionId,
                        memberIdOrIdentifier: identifier || memberId,
                        memberName: memberName || 'Unknown'
                    });
                });
            });
            
            tabContent.querySelectorAll('.btn-transfer').forEach(btn => {
                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const memberId = this.getAttribute('data-member-id');
                    const identifier = this.getAttribute('data-identifier');
                    const memberName = this.getAttribute('data-member-name');
                    post('requestTransferConfirm', {
                        factionId: factionId,
                        newBossMemberIdOrIdentifier: identifier || memberId,
                        memberName: memberName || 'Unknown'
                    });
                });
            });
        }
    }
    
    function getRankLabel(rank) {
        const rankLabels = {
            'boss': 'Boss',
            'big_homie': 'Big Homie',
            'shot_caller': 'Shot Caller',
            'member': 'Member',
            'runner': 'Runner'
        };
        return rankLabels[rank] || rank;
    }
    
    function showSetRankDialog(memberId, identifier, currentRank, factionId) {
        const html = `
            <div class="modal-overlay" id="set-rank-modal">
                <div class="modal-content">
                    <div class="modal-header">
                        <h3>Set Member Rank</h3>
                        <button class="modal-close" id="close-rank-modal">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Select Rank</label>
                            <select id="member-rank" class="form-select">
                                <option value="runner" ${currentRank === 'runner' ? 'selected' : ''}>Runner</option>
                                <option value="member" ${currentRank === 'member' ? 'selected' : ''}>Member</option>
                                <option value="shot_caller" ${currentRank === 'shot_caller' ? 'selected' : ''}>Shot Caller</option>
                                <option value="big_homie" ${currentRank === 'big_homie' ? 'selected' : ''}>Big Homie</option>
                                <option value="boss" ${currentRank === 'boss' ? 'selected' : ''}>Boss</option>
                            </select>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-cancel" id="cancel-set-rank">Cancel</button>
                        <button class="btn-submit" id="save-set-rank" data-member-id="${memberId}" data-identifier="${identifier}">Set Rank</button>
                    </div>
                </div>
            </div>
        `;
        document.body.insertAdjacentHTML('beforeend', html);
        
        const modal = document.getElementById('set-rank-modal');
        const closeBtn = document.getElementById('close-rank-modal');
        const cancelBtn = document.getElementById('cancel-set-rank');
        const saveBtn = document.getElementById('save-set-rank');
        
        const closeModal = () => {
            if (modal) modal.remove();
        };
        
        closeBtn?.addEventListener('click', closeModal);
        cancelBtn?.addEventListener('click', closeModal);
        modal?.addEventListener('click', function(e) {
            if (e.target === modal) closeModal();
        });
        
        saveBtn?.addEventListener('click', function() {
            const rank = document.getElementById('member-rank').value;
            const memberId = this.getAttribute('data-member-id');
            const identifier = this.getAttribute('data-identifier');
            post('adminSetMemberRank', { 
                factionId: factionId,
                memberIdOrIdentifier: identifier || memberId,
                rank: rank
            });
            closeModal();
        });
    }
    
    function showAddWarningDialog(memberId, memberName, factionId) {
        post('requestAddWarning', {
            factionId: factionId,
            memberId: memberId,
            memberName: memberName || 'Unknown'
        });
    }

    function escapeHtml(s) {
        if (s == null) return '';
        const div = document.createElement('div');
        div.textContent = s;
        return div.innerHTML;
    }

    /** Escape string for safe use inside template literals (e.g. confirm/prompt) to prevent injection */
    function escapeForTemplate(s) {
        if (s == null) return '';
        return String(s).replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$/g, '\\$');
    }

    // ============================================================
    // IN-NUI TOAST NOTIFICATION SYSTEM
    // Matches the dark zinc UI design (#18181b background, zinc palette)
    // ============================================================

    function showToast(message, type) {
        type = type || 'error';
        var container = document.getElementById('nui-toast-container');
        if (!container) {
            container = document.createElement('div');
            container.id = 'nui-toast-container';
            container.style.cssText = 'position:fixed;top:20px;left:50%;transform:translateX(-50%);z-index:99999;display:flex;flex-direction:column;align-items:center;gap:8px;pointer-events:none;min-width:280px;max-width:460px;';
            document.body.appendChild(container);
        }

        var colors = {
            success: { bg: 'rgba(34,197,94,0.12)',  border: 'rgba(34,197,94,0.45)',  accent: '#22c55e' },
            error:   { bg: 'rgba(239,68,68,0.12)',  border: 'rgba(239,68,68,0.45)',  accent: '#ef4444' },
            warning: { bg: 'rgba(245,158,11,0.12)', border: 'rgba(245,158,11,0.45)', accent: '#f59e0b' },
            info:    { bg: 'rgba(59,130,246,0.12)',  border: 'rgba(59,130,246,0.45)', accent: '#3b82f6' }
        };
        var icons = {
            success: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>',
            error:   '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6L6 18M6 6l12 12"/></svg>',
            warning: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>',
            info:    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>'
        };

        var c = colors[type] || colors.info;
        var icon = icons[type] || icons.info;

        var toast = document.createElement('div');
        toast.style.cssText = 'background:#18181b;border:1px solid ' + c.border + ';border-left:3px solid ' + c.accent + ';border-radius:10px;padding:12px 16px;display:flex;align-items:flex-start;gap:10px;pointer-events:auto;box-shadow:0 4px 24px rgba(0,0,0,0.6);transform:translateX(120%);transition:transform 0.28s cubic-bezier(0.34,1.56,0.64,1),opacity 0.28s ease;opacity:0;min-width:220px;';
        toast.innerHTML = '<div style="color:' + c.accent + ';flex-shrink:0;margin-top:1px;">' + icon + '</div><div style="color:#e4e4e7;font-size:0.875rem;line-height:1.45;font-family:\'DM Sans\',sans-serif;flex:1;">' + escapeHtml(message) + '</div>';
        container.appendChild(toast);

        requestAnimationFrame(function() {
            requestAnimationFrame(function() {
                toast.style.transform = 'translateX(0)';
                toast.style.opacity = '1';
            });
        });

        setTimeout(function() {
            toast.style.transform = 'translateX(120%)';
            toast.style.opacity = '0';
            setTimeout(function() { if (toast.parentNode) toast.parentNode.removeChild(toast); }, 300);
        }, 3800);
    }

    function showConfirm(message, onConfirm) {
        var existing = document.getElementById('nui-confirm-overlay');
        if (existing) existing.parentNode.removeChild(existing);

        var overlay = document.createElement('div');
        overlay.id = 'nui-confirm-overlay';
        overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.72);z-index:99998;display:flex;align-items:center;justify-content:center;';
        overlay.innerHTML = '<div style="background:#18181b;border:1px solid #3f3f46;border-radius:14px;padding:28px;max-width:360px;width:90%;box-shadow:0 8px 48px rgba(0,0,0,0.7);">'
            + '<div style="color:#e4e4e7;font-size:0.9375rem;font-weight:500;margin-bottom:22px;line-height:1.5;font-family:\'DM Sans\',sans-serif;">' + escapeHtml(message) + '</div>'
            + '<div style="display:flex;gap:10px;justify-content:flex-end;">'
            + '<button id="nui-confirm-cancel" style="background:#27272a;border:1px solid #3f3f46;color:#a1a1aa;padding:8px 22px;border-radius:8px;cursor:pointer;font-family:\'DM Sans\',sans-serif;font-size:0.875rem;">Cancel</button>'
            + '<button id="nui-confirm-ok" style="background:#ef4444;border:none;color:#fff;padding:8px 22px;border-radius:8px;cursor:pointer;font-family:\'DM Sans\',sans-serif;font-size:0.875rem;font-weight:600;">Confirm</button>'
            + '</div></div>';
        document.body.appendChild(overlay);

        document.getElementById('nui-confirm-ok').addEventListener('click', function() {
            overlay.parentNode.removeChild(overlay);
            onConfirm();
        });
        document.getElementById('nui-confirm-cancel').addEventListener('click', function() {
            overlay.parentNode.removeChild(overlay);
        });
    }

    function renderCKTab(content) {
        if (!content || !content.step) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
            return;
        }

        if (content.step === 'select_faction') {
            const factions = content.factions || [];
            if (factions.length === 0) {
                tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No factions found. Contact an admin to create factions first.</span></div>';
                return;
            }

            let html = '<div class="ck-container"><h3>Select Faction</h3><p style="color: #71717a; font-size: 13px; margin-bottom: 20px;">Select the faction containing the player you want to submit a CK request for</p><div class="faction-list">';
            factions.forEach(faction => {
                // Generate unique color based on faction ID
                const hue = ((faction.id * 13) % 360);
                const color = `hsl(${hue}, 70%, 55%)`;
                const initial = (faction.label || faction.name || 'F').charAt(0).toUpperCase();
                
                html += `<div class="faction-item" data-faction-id="${faction.id}">
                    <div style="display: flex; align-items: center; gap: 14px; flex: 1;">
                        <div class="faction-icon-small" style="background: ${color}; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3), 0 0 0 2px rgba(255, 255, 255, 0.1);">
                            ${escapeHtml(initial)}
                        </div>
                        <div style="flex: 1;">
                            <div class="faction-name">${escapeHtml(faction.label || faction.name)}</div>
                            <div style="color: #71717a; font-size: 12px; margin-top: 2px;">Click to select</div>
                        </div>
                    </div>
                    <button class="btn-select" data-faction-id="${faction.id}">Select</button>
                </div>`;
            });
            html += '</div></div>';
            tabContent.innerHTML = html;
            
            // Attach click handlers
            tabContent.querySelectorAll('.btn-select, .faction-item').forEach(item => {
                item.addEventListener('click', function() {
                    const factionId = this.getAttribute('data-faction-id');
                    if (factionId) {
                        post('selectCKFaction', { factionId: parseInt(factionId) });
                    }
                });
            });
        } else if (content.step === 'select_player') {
            const players = content.players || [];
            const factionLabel = content.factionLabel || 'Unknown';
            
            if (players.length === 0) {
                tabContent.innerHTML = `<div class="empty-state"><span class="empty-text">No online players from ${escapeHtml(factionLabel)}</span></div><button class="btn-back" style="margin-top: 20px;" data-action="ckBack">Back</button>`;
                // Attach event listener for back button
                const backBtn = tabContent.querySelector('.btn-back[data-action="ckBack"]');
                if (backBtn) {
                    backBtn.addEventListener('click', function() {
                        post('ckBack', {});
                    });
                }
                return;
            }
            
            let html = `<div class="ck-container"><h3>Select Member - ${escapeHtml(factionLabel)}</h3><p style="color: #71717a; font-size: 13px; margin-bottom: 20px;">Choose the member you want to submit a CK request for</p><div class="player-list">`;
            players.forEach(player => {
                const initials = (player.name || 'U').split(' ').map(n => n.charAt(0)).join('').toUpperCase().substring(0, 2);
                const nameHash = (player.name || '').split('').reduce((acc, char) => acc + char.charCodeAt(0), 0);
                const hue = (nameHash * 7) % 360;
                const isOnline = player.online === true || player.online === 1;
                const color = isOnline ? `hsl(${hue}, 65%, 50%)` : '#52525b';
                const serverId = player.serverId || 0;

                html += `<div class="player-item" data-identifier="${escapeHtml(player.identifier)}" data-name="${escapeHtml(player.name)}" data-server-id="${serverId}">
                    <div style="display: flex; align-items: center; gap: 14px; flex: 1;">
                        <div class="player-icon-small" style="background: ${color}; box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3), 0 0 0 2px rgba(255, 255, 255, 0.1);">
                            ${escapeHtml(initials)}
                        </div>
                        <div style="flex: 1;">
                            <div class="player-name">${escapeHtml(player.name)}</div>
                            <div style="color: ${isOnline ? '#22c55e' : '#71717a'}; font-size: 12px; margin-top: 2px;">${isOnline ? '● Online (ID: ' + serverId + ')' : '○ Offline'}</div>
                        </div>
                    </div>
                    <button class="btn-select" data-identifier="${escapeHtml(player.identifier)}" data-name="${escapeHtml(player.name)}" data-server-id="${serverId}">Select</button>
                </div>`;
            });
            html += '</div><button class="btn-back" data-action="ckBack">Back</button></div>';
            tabContent.innerHTML = html;
            
            // Attach event listener for back button
            const backBtn = tabContent.querySelector('.btn-back[data-action="ckBack"]');
            if (backBtn) {
                backBtn.addEventListener('click', function() {
                    post('ckBack', {});
                });
            }
            
            // Attach click handlers
            tabContent.querySelectorAll('.btn-select, .player-item').forEach(item => {
                item.addEventListener('click', function() {
                    const identifier = this.getAttribute('data-identifier');
                    const name = this.getAttribute('data-name');
                    const serverId = this.getAttribute('data-server-id');
                    if (identifier && name && serverId) {
                        post('selectCKPlayer', {
                            identifier: identifier,
                            name: name,
                            serverId: parseInt(serverId)
                        });
                    }
                });
            });
        } else if (content.step === 'enter_reason') {
            const targetName = content.targetName || 'Unknown';
            const serverId = content.serverId || 0;
            
            tabContent.innerHTML = `
                <div class="ck-container">
                    <h3>CK Request</h3>
                    <div class="form-group">
                        <label>Target:</label>
                        <div class="target-info">${escapeHtml(targetName)} (ID: ${serverId})</div>
                    </div>
                    <div class="form-group">
                        <label for="ck-reason">Reason:</label>
                        <textarea id="ck-reason" class="form-textarea" placeholder="Enter reason for CK request..." rows="5"></textarea>
                    </div>
                    <div class="form-actions">
                        <button class="btn-submit" id="btn-submit-ck">Submit CK Request</button>
                        <button class="btn-cancel" data-action="ckCancel">Cancel</button>
                    </div>
                </div>
            `;
            
            // Attach submit handler
            const submitBtn = tabContent.querySelector('#btn-submit-ck');
            const reasonInput = tabContent.querySelector('#ck-reason');
            const cancelBtn = tabContent.querySelector('.btn-cancel[data-action="ckCancel"]');
            if (submitBtn && reasonInput) {
                submitBtn.addEventListener('click', function() {
                    const reason = reasonInput.value.trim();
                    if (!reason) {
                        showToast('Please enter a reason for the CK request', 'warning');
                        return;
                    }
                    post('submitCKRequest', {
                        targetIdentifier: content.targetIdentifier,
                        targetName: targetName,
                        serverId: serverId,
                        reason: reason
                    });
                });
            }
            if (cancelBtn) {
                cancelBtn.addEventListener('click', function() {
                    post('ckCancel', {});
                });
            }
        } else {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
        }
    }

    function renderReportTab(content) {
        if (!content || !content.step) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
            return;
        }

        if (content.step === 'select_report_type') {
            tabContent.innerHTML = `
                <div class="report-container">
                    <h3>Faction Report</h3>
                    <div class="form-group">
                        <label>Report On:</label>
                        <div class="radio-group">
                            <label class="radio-label">
                                <input type="radio" name="report-on" value="own" checked>
                                <span>My Faction</span>
                            </label>
                            <label class="radio-label">
                                <input type="radio" name="report-on" value="other">
                                <span>Another Faction</span>
                            </label>
                        </div>
                    </div>
                    <button class="btn-submit" id="btn-continue-report">Continue</button>
                </div>
            `;
            
            const continueBtn = tabContent.querySelector('#btn-continue-report');
            if (continueBtn) {
                continueBtn.addEventListener('click', function() {
                    const reportOn = tabContent.querySelector('input[name="report-on"]:checked').value;
                    if (reportOn === 'other') {
                        post('reportSelectOther', {});
                    } else {
                        post('reportSelectOwn', {});
                    }
                });
            }
        } else if (content.step === 'select_target_faction') {
            const factions = content.factions || [];
            if (factions.length === 0) {
                tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No other factions available</span></div>';
                return;
            }
            
            let html = '<div class="report-container"><h3>Select Faction to Report</h3><div class="faction-list">';
            factions.forEach(faction => {
                html += `<div class="faction-item" data-faction-id="${faction.id}">
                    <div class="faction-name">${escapeHtml(faction.label || faction.name)}</div>
                    <button class="btn-select" data-faction-id="${faction.id}">Select</button>
                </div>`;
            });
            html += '</div><button class="btn-back" data-action="reportBack">Back</button></div>';
            tabContent.innerHTML = html;
            
            tabContent.querySelectorAll('.btn-select, .faction-item').forEach(item => {
                item.addEventListener('click', function() {
                    const factionId = this.getAttribute('data-faction-id');
                    if (factionId) {
                        post('reportSelectFaction', { factionId: parseInt(factionId) });
                    }
                });
            });
            
            // Attach event listener for back button
            const backBtn = tabContent.querySelector('.btn-back[data-action="reportBack"]');
            if (backBtn) {
                backBtn.addEventListener('click', function() {
                    post('reportCancel', {});
                });
            }
        } else if (content.step === 'enter_details') {
            const targetFactionId = content.targetFactionId || null;
            
            tabContent.innerHTML = `
                <div class="report-container">
                    <h3>Faction Report</h3>
                    <div class="form-group">
                        <label for="report-type">Report Type:</label>
                        <div class="form-select-wrapper">
                            <select id="report-type" class="form-select">
                                <option value="violation">Violation</option>
                                <option value="dispute">Territory Dispute</option>
                                <option value="member">Member Issue</option>
                                <option value="other">Other</option>
                            </select>
                        </div>
                    </div>
                    <div class="form-group">
                        <label for="report-details">Report Details:</label>
                        <textarea id="report-details" class="form-textarea" placeholder="Describe the issue..." rows="5"></textarea>
                    </div>
                    <div class="form-actions">
                        <button class="btn-submit" id="btn-submit-report">Submit Report</button>
                        <button class="btn-cancel" data-action="reportCancel">Cancel</button>
                    </div>
                </div>
            `;
            
            const submitBtn = tabContent.querySelector('#btn-submit-report');
            const typeSelect = tabContent.querySelector('#report-type');
            const detailsInput = tabContent.querySelector('#report-details');
            const cancelBtn = tabContent.querySelector('.btn-cancel[data-action="reportCancel"]');
            if (submitBtn && typeSelect && detailsInput) {
                submitBtn.addEventListener('click', function() {
                    const reportType = typeSelect.value;
                    const details = detailsInput.value.trim();
                    if (!details) {
                        showToast('Please enter report details', 'warning');
                        return;
                    }
                    post('submitReport', {
                        reportType: reportType,
                        details: details,
                        targetFactionId: targetFactionId
                    });
                });
            }
            if (cancelBtn) {
                cancelBtn.addEventListener('click', function() {
                    post('reportCancel', {});
                });
            }
        } else {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
        }
    }

    // Admin tab rendering functions
    function renderAdminWeaponTab(content) {
        if (content.step === 'select_faction') {
            const factions = content.factions || [];
            if (factions.length === 0) {
                tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No factions available</span></div>';
                return;
            }
            
            let html = '<div class="ck-container"><div class="section-header"><h3>Select Faction for Weapon Management</h3><p class="section-subtitle">Choose a faction to view, register, or delete weapons</p></div><div class="faction-list grid-layout">';
            factions.forEach(faction => {
                const initials = (faction.label || faction.name).substring(0, 2).toUpperCase();
                const hue = ((faction.id * 13) % 360);
                const color = `hsl(${hue}, 70%, 60%)`;
                const colorLight = `hsl(${hue}, 70%, 65%)`;
                html += `<div class="faction-item-modern" data-faction-id="${faction.id}" data-faction-label="${escapeHtml(faction.label || faction.name)}">
                    <div class="faction-item-body">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <div class="faction-color-bubble" style="background: ${color};"></div>
                            <div style="flex: 1;">
                                <div class="faction-name-modern">${escapeHtml(faction.label || faction.name)}</div>
                                <div class="faction-description-modern">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display: inline-block; vertical-align: middle; margin-right: 6px; opacity: 0.6;">
                                        <path d="M12 2L2 7L12 12L22 7L12 2Z"></path>
                                        <path d="M2 17L12 22L22 17"></path>
                                        <path d="M2 12L12 17L22 12"></path>
                                    </svg>
                                    Manage weapons for this faction
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="faction-item-footer">
                        <button class="btn-select-modern" data-faction-id="${faction.id}" data-faction-label="${escapeHtml(faction.label || faction.name)}" style="--btn-color: ${color}; --btn-color-light: ${colorLight};">
                            <span>Select</span>
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-left: 8px;">
                                <path d="M5 12h14M12 5l7 7-7 7"></path>
                            </svg>
                        </button>
                    </div>
                </div>`;
            });
            html += '</div></div>';
            tabContent.innerHTML = html;
            
            // Attach event listeners for faction selection
            tabContent.querySelectorAll('.btn-select-modern, .faction-item-modern').forEach(item => {
                item.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const factionId = this.getAttribute('data-faction-id') || this.closest('.faction-item-modern')?.getAttribute('data-faction-id');
                    const factionLabel = this.getAttribute('data-faction-label') || this.closest('.faction-item-modern')?.getAttribute('data-faction-label');
                    if (factionId) {
                        post('adminSelectWeaponFaction', { factionId: parseInt(factionId), factionLabel: factionLabel });
                    }
                });
            });
        } else if (content.step === 'register_weapon') {
            const factionLabel = content.factionLabel || 'Unknown';
            tabContent.innerHTML = `
                <div class="report-container">
                    <h3>Register Weapon - ${escapeHtml(factionLabel)}</h3>
                    <div class="form-group">
                        <label for="weapon-name">Display Name:</label>
                        <input type="text" id="weapon-name" class="form-select" placeholder="e.g. AK-47, Glock 17" required>
                    </div>
                    <div class="form-group">
                        <label for="serial-number">Serial Number: *</label>
                        <input type="text" id="serial-number" class="form-select" placeholder="e.g. SN-123456" required>
                    </div>
                    <div class="form-group">
                        <label for="weapon-hash">Weapon Spawn Code:</label>
                        <input type="text" id="weapon-hash" class="form-select" placeholder="e.g. weapon_ak47 or -1074790547">
                    </div>
                    <div class="form-actions">
                        <button class="btn-submit" id="btn-submit-weapon">Register Weapon</button>
                        <button class="btn-cancel" data-action="weaponCancel">Cancel</button>
                    </div>
                </div>
            `;
            
            const submitBtn = tabContent.querySelector('#btn-submit-weapon');
            const cancelBtn = tabContent.querySelector('.btn-cancel[data-action="weaponCancel"]');
            if (submitBtn) {
                submitBtn.addEventListener('click', function() {
                    const weaponName = tabContent.querySelector('#weapon-name').value.trim();
                    const serialNumber = tabContent.querySelector('#serial-number').value.trim();
                    const weaponHash = tabContent.querySelector('#weapon-hash').value.trim();
                    if (!weaponName || !serialNumber) {
                        showToast('Please fill in weapon name and serial number', 'warning');
                        return;
                    }
                    post('adminSubmitWeapon', {
                        factionId: content.factionId,
                        weaponName: weaponName,
                        serialNumber: serialNumber,
                        weaponHash: weaponHash || null
                    });
                });
            }
            if (cancelBtn) {
                cancelBtn.addEventListener('click', function() {
                    post('requestTabData', { tab: 'weapons', isAdmin: true });
                });
            }
        } else if (content.step === 'view_weapons') {
            const factionId = content.factionId;
            const factionLabel = content.factionLabel || 'Unknown';
            const weapons = content.weapons || [];
            
            let html = `
                <div class="ck-container">
                    <div class="section-header">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
                            <div>
                                <h3>Weapons - ${escapeHtml(factionLabel)}</h3>
                                <p class="section-subtitle">Manage registered weapons for this faction</p>
                            </div>
                            <button class="btn-submit" id="btn-register-new-weapon" style="margin: 0;">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 6px;">
                                    <path d="M12 5v14M5 12h14"></path>
                                </svg>
                                Register New Weapon
                            </button>
                        </div>
                    </div>
            `;
            
            if (weapons.length === 0) {
                html += '<div class="empty-state"><span class="empty-text">No weapons registered for this faction</span></div>';
            } else {
                html += '<div class="weapons-list" style="display: flex; flex-direction: column; gap: 0.75rem;">';
                weapons.forEach(weapon => {
                    const loggedDate = weapon.logged_at ? formatDate(weapon.logged_at) : 'Unknown';
                    const possessedBy = weapon.possessed_by || [];
                    const hasPossession = possessedBy.length > 0;
                    
                    html += `
                        <div class="weapon-item" style="background: #27272a; border: 1px solid ${hasPossession ? '#3b82f6' : '#3f3f46'}; border-radius: 10px; padding: 1rem; display: flex; flex-direction: column; gap: 0.75rem;">
                            <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                                <div style="flex: 1;">
                                    <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem; font-size: 1rem; display: flex; align-items: center; gap: 0.5rem;">
                                        ${escapeHtml(weapon.weapon_name || 'Unknown Weapon')}
                                        ${hasPossession ? `<span style="background: #3b82f6; color: #fff; padding: 0.125rem 0.5rem; border-radius: 4px; font-size: 0.75rem; font-weight: 600;">IN USE</span>` : ''}
                                    </div>
                                    <div style="color: #71717a; font-size: 0.8125rem; margin-bottom: 0.125rem;">
                                        Serial: <span style="color: #a1a1aa; font-weight: 500;">${escapeHtml(weapon.serial_number || 'N/A')}</span>
                                    </div>
                                    <div style="color: #71717a; font-size: 0.75rem; margin-top: 0.25rem;">
                                        Logged: ${loggedDate}
                                    </div>
                                </div>
                                <button class="btn-delete-weapon" data-weapon-id="${weapon.id}" style="background: #ef4444; color: #fff; border: none; padding: 0.5rem 1rem; border-radius: 6px; cursor: pointer; font-weight: 600; font-size: 0.875rem; display: flex; align-items: center; gap: 0.5rem; transition: background 0.2s; flex-shrink: 0;" onmouseover="this.style.background='#dc2626'" onmouseout="this.style.background='#ef4444'">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                                    </svg>
                                    Delete
                                </button>
                            </div>
                            ${hasPossession ? `
                                <div style="background: ${hasPossession ? 'rgba(59, 130, 246, 0.1)' : 'transparent'}; border: 1px solid ${hasPossession ? 'rgba(59, 130, 246, 0.3)' : 'transparent'}; border-radius: 8px; padding: 0.75rem;">
                                    <div style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; color: #3b82f6; font-size: 0.8125rem; font-weight: 600;">
                                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                            <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                                            <circle cx="9" cy="7" r="4"></circle>
                                            <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
                                            <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
                                        </svg>
                                        Currently Possessed By:
                                    </div>
                                    <div style="display: flex; flex-direction: column; gap: 0.5rem;">
                                        ${possessedBy.map(possessor => `
                                            <div style="display: flex; align-items: center; gap: 0.75rem; padding: 0.5rem; background: rgba(59, 130, 246, 0.05); border-radius: 6px;">
                                                <div style="width: 32px; height: 32px; background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 0.75rem; flex-shrink: 0;">
                                                    ${escapeHtml((possessor.name || 'Unknown').charAt(0).toUpperCase())}
                                                </div>
                                                <div style="flex: 1;">
                                                    <div style="color: #fff; font-weight: 600; font-size: 0.875rem;">
                                                        ${escapeHtml(possessor.name || 'Unknown Player')}
                                                    </div>
                                                    <div style="color: #71717a; font-size: 0.75rem;">
                                                        ID: ${possessor.serverId || 'N/A'}
                                                    </div>
                                                </div>
                                            </div>
                                        `).join('')}
                                    </div>
                                </div>
                            ` : `
                                <div style="color: #71717a; font-size: 0.8125rem; display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem; background: rgba(113, 113, 122, 0.05); border-radius: 6px;">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                        <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path>
                                    </svg>
                                    Not currently in possession
                                </div>
                            `}
                        </div>
                    `;
                });
                html += '</div>';
            }
            
            html += `
                    <div style="margin-top: 1.5rem;">
                        <button class="btn-cancel" id="btn-back-to-factions" style="width: 100%;">Back to Faction Selection</button>
                    </div>
                </div>
            `;
            
            tabContent.innerHTML = html;
            
            // Attach event listeners
            const registerBtn = tabContent.querySelector('#btn-register-new-weapon');
            if (registerBtn) {
                registerBtn.addEventListener('click', function() {
                    // Show register weapon form directly without server call - Modern sleek design
                    tabContent.innerHTML = `
                        <div class="report-container" style="max-width: 100%;">
                            <div style="margin-bottom: 2rem;">
                                <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem;">
                                    <div style="width: 40px; height: 40px; background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); border-radius: 10px; display: flex; align-items: center; justify-content: center;">
                                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: #fff;">
                                            <path d="M12 5v14M5 12h14"></path>
                                        </svg>
                                    </div>
                                    <div>
                                        <h3 style="margin: 0; color: #fff; font-size: 1.25rem; font-weight: 700;">Register New Weapon</h3>
                                        <p style="margin: 0.25rem 0 0 0; color: #71717a; font-size: 0.875rem;">${escapeHtml(factionLabel)}</p>
                                    </div>
                                </div>
                            </div>
                            
                            <div class="form-group" style="margin-bottom: 1.5rem;">
                                <label for="weapon-name" style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.75rem; color: #a1a1aa; font-size: 0.8125rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                        <path d="M12 2L2 7l10 5 10-5-10-5z"></path>
                                        <path d="M2 17l10 5 10-5"></path>
                                        <path d="M2 12l10 5 10-5"></path>
                                    </svg>
                                    Display Name
                                </label>
                                <input type="text" id="weapon-name" class="form-select" placeholder="e.g. AK-47, M4A1, Glock 17" required style="width: 100%; padding: 14px 18px; background: linear-gradient(135deg, #27272a 0%, #1f1f23 100%); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 12px; color: #e4e4e7; font-size: 15px; font-weight: 500; font-family: inherit; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.05);">
                            </div>
                            
                            <div class="form-group" style="margin-bottom: 1.5rem;">
                                <label for="serial-number" style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.75rem; color: #a1a1aa; font-size: 0.8125rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                        <rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect>
                                        <path d="M7 11V7a5 5 0 0 1 10 0v4"></path>
                                    </svg>
                                    Serial Number
                                    <span style="color: #ef4444; margin-left: 0.25rem;">*</span>
                                </label>
                                <input type="text" id="serial-number" class="form-select" placeholder="e.g. SN-123456, WPN-789012" required style="width: 100%; padding: 14px 18px; background: linear-gradient(135deg, #27272a 0%, #1f1f23 100%); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 12px; color: #e4e4e7; font-size: 15px; font-weight: 500; font-family: inherit; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.05);">
                            </div>
                            <div class="form-group" style="margin-bottom: 1.5rem;">
                                <label for="weapon-hash" style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.75rem; color: #a1a1aa; font-size: 0.8125rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                        <polyline points="16 18 22 12 16 6"></polyline>
                                        <polyline points="8 6 2 12 8 18"></polyline>
                                    </svg>
                                    Weapon Spawn Code
                                    <span style="color: #71717a; font-size: 0.75rem; font-weight: 400; text-transform: none; margin-left: 0.5rem;">(for gun drops)</span>
                                </label>
                                <input type="text" id="weapon-hash" class="form-select" placeholder="e.g. weapon_ak47 or -1074790547" style="width: 100%; padding: 14px 18px; background: linear-gradient(135deg, #27272a 0%, #1f1f23 100%); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 12px; color: #e4e4e7; font-size: 15px; font-weight: 500; font-family: inherit; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1); box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.05);">
                            </div>
                            <div class="form-actions" style="display: flex; gap: 0.75rem; margin-top: 2rem;">
                                <button class="btn-submit" id="btn-submit-weapon" style="flex: 1; padding: 14px 24px; background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); color: white; border: none; border-radius: 12px; font-size: 14px; font-weight: 600; cursor: pointer; transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1); box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4); display: flex; align-items: center; justify-content: center; gap: 0.5rem; text-transform: uppercase; letter-spacing: 0.5px;">
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                                        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
                                        <polyline points="22 4 12 14.01 9 11.01"></polyline>
                                    </svg>
                                    Register Weapon
                                </button>
                                <button class="btn-cancel" id="btn-cancel-register" style="flex: 1; padding: 14px 24px; background: #27272a; color: #e4e4e7; border: 1px solid #3f3f46; border-radius: 12px; font-size: 14px; font-weight: 600; cursor: pointer; transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1); display: flex; align-items: center; justify-content: center; gap: 0.5rem;">
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                                        <line x1="18" y1="6" x2="6" y2="18"></line>
                                        <line x1="6" y1="6" x2="18" y2="18"></line>
                                    </svg>
                                    Cancel
                                </button>
                            </div>
                        </div>
                    `;
                    
                    // Add hover effects for inputs
                    const inputs = tabContent.querySelectorAll('input.form-select');
                    inputs.forEach(input => {
                        input.addEventListener('focus', function() {
                            this.style.background = 'linear-gradient(135deg, #3f3f46 0%, #35353a 100%)';
                            this.style.borderColor = '#3b82f6';
                            this.style.boxShadow = '0 0 0 4px rgba(59, 130, 246, 0.15), 0 6px 16px rgba(0, 0, 0, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.05)';
                            this.style.transform = 'translateY(-1px)';
                        });
                        input.addEventListener('blur', function() {
                            this.style.background = 'linear-gradient(135deg, #27272a 0%, #1f1f23 100%)';
                            this.style.borderColor = 'rgba(255, 255, 255, 0.1)';
                            this.style.boxShadow = '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.05)';
                            this.style.transform = 'translateY(0)';
                        });
                        input.addEventListener('mouseenter', function() {
                            if (document.activeElement !== this) {
                                this.style.background = 'linear-gradient(135deg, #3f3f46 0%, #35353a 100%)';
                                this.style.borderColor = 'rgba(59, 130, 246, 0.4)';
                                this.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.2), 0 0 0 1px rgba(59, 130, 246, 0.2), inset 0 1px 0 rgba(255, 255, 255, 0.05)';
                                this.style.transform = 'translateY(-1px)';
                            }
                        });
                        input.addEventListener('mouseleave', function() {
                            if (document.activeElement !== this) {
                                this.style.background = 'linear-gradient(135deg, #27272a 0%, #1f1f23 100%)';
                                this.style.borderColor = 'rgba(255, 255, 255, 0.1)';
                                this.style.boxShadow = '0 2px 8px rgba(0, 0, 0, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.05)';
                                this.style.transform = 'translateY(0)';
                            }
                        });
                    });
                    
                    // Add hover effects for buttons
                    const submitBtn = tabContent.querySelector('#btn-submit-weapon');
                    if (submitBtn) {
                        submitBtn.addEventListener('mouseenter', function() {
                            this.style.background = 'linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%)';
                            this.style.boxShadow = '0 6px 16px rgba(59, 130, 246, 0.5)';
                            this.style.transform = 'translateY(-2px)';
                        });
                        submitBtn.addEventListener('mouseleave', function() {
                            this.style.background = 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)';
                            this.style.boxShadow = '0 4px 12px rgba(59, 130, 246, 0.4)';
                            this.style.transform = 'translateY(0)';
                        });
                        submitBtn.addEventListener('mousedown', function() {
                            this.style.transform = 'translateY(0)';
                        });
                    }
                    
                    const cancelBtn = tabContent.querySelector('#btn-cancel-register');
                    if (cancelBtn) {
                        cancelBtn.addEventListener('mouseenter', function() {
                            this.style.background = '#3f3f46';
                            this.style.borderColor = '#52525b';
                            this.style.transform = 'translateY(-1px)';
                        });
                        cancelBtn.addEventListener('mouseleave', function() {
                            this.style.background = '#27272a';
                            this.style.borderColor = '#3f3f46';
                            this.style.transform = 'translateY(0)';
                        });
                        
                        // Attach click handler for cancel button
                        cancelBtn.addEventListener('click', function() {
                            // Refresh weapons list view
                            post('adminViewWeapons', { factionId: factionId });
                        });
                    }
                    
                    // Attach click handler for submit button
                    if (submitBtn) {
                        submitBtn.addEventListener('click', function() {
                            const weaponName = tabContent.querySelector('#weapon-name').value.trim();
                            const serialNumber = tabContent.querySelector('#serial-number').value.trim();
                            const weaponHash = tabContent.querySelector('#weapon-hash').value.trim();
                            if (!weaponName || !serialNumber) {
                                showToast('Please fill in weapon name and serial number', 'warning');
                                return;
                            }
                            post('adminSubmitWeapon', {
                                factionId: factionId,
                                weaponName: weaponName,
                                serialNumber: serialNumber,
                                weaponHash: weaponHash || null
                            });
                        });
                    }
                });
            }
            
            // Attach delete button listeners
            tabContent.querySelectorAll('.btn-delete-weapon').forEach(btn => {
                btn.addEventListener('click', function() {
                    const weaponId = this.getAttribute('data-weapon-id');
                    if (weaponId) {
                        post('requestDeleteWeaponConfirm', { weaponId: parseInt(weaponId) });
                    }
                });
            });
            
            // Back button
            const backBtn = tabContent.querySelector('#btn-back-to-factions');
            if (backBtn) {
                backBtn.addEventListener('click', function() {
                    post('requestTabData', { tab: 'weapons', isAdmin: true });
                });
            }
        }
    }

    function renderMemberWeaponsTab(content) {
        const weapons = content.weapons || content.items || [];
        let html = '<div class="ck-container"><div class="section-header"><h3>Faction Weapons</h3><p class="section-subtitle">Registered weapons and who currently has them</p></div>';
        if (weapons.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No weapons registered for your faction</span></div>';
        } else {
            html += '<div class="weapons-list" style="display: flex; flex-direction: column; gap: 0.75rem;">';
            weapons.forEach(weapon => {
                const loggedDate = weapon.logged_at ? formatDate(weapon.logged_at) : 'Unknown';
                const possessedBy = weapon.possessed_by || [];
                const hasPossession = possessedBy.length > 0;
                html += `
                    <div class="weapon-item" style="background: #27272a; border: 1px solid ${hasPossession ? '#3b82f6' : '#3f3f46'}; border-radius: 10px; padding: 1rem; display: flex; flex-direction: column; gap: 0.75rem;">
                        <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                            <div style="flex: 1;">
                                <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem; font-size: 1rem; display: flex; align-items: center; gap: 0.5rem;">
                                    ${escapeHtml(weapon.weapon_name || 'Unknown Weapon')}
                                    ${hasPossession ? `<span style="background: #3b82f6; color: #fff; padding: 0.125rem 0.5rem; border-radius: 4px; font-size: 0.75rem; font-weight: 600;">IN USE</span>` : ''}
                                </div>
                                <div style="color: #71717a; font-size: 0.8125rem; margin-bottom: 0.125rem;">
                                    Serial: <span style="color: #a1a1aa; font-weight: 500;">${escapeHtml(weapon.serial_number || 'N/A')}</span>
                                </div>
                                <div style="color: #71717a; font-size: 0.75rem; margin-top: 0.25rem;">
                                    Logged: ${loggedDate}
                                </div>
                            </div>
                        </div>
                        ${hasPossession ? `
                            <div style="background: rgba(59, 130, 246, 0.1); border: 1px solid rgba(59, 130, 246, 0.3); border-radius: 8px; padding: 0.75rem;">
                                <div style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; color: #3b82f6; font-size: 0.8125rem; font-weight: 600;">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                                        <circle cx="9" cy="7" r="4"></circle>
                                        <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
                                        <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
                                    </svg>
                                    Currently Possessed By:
                                </div>
                                <div style="display: flex; flex-direction: column; gap: 0.5rem;">
                                    ${possessedBy.map(possessor => `
                                        <div style="display: flex; align-items: center; gap: 0.75rem; padding: 0.5rem; background: rgba(59, 130, 246, 0.05); border-radius: 6px;">
                                            <div style="width: 32px; height: 32px; background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 0.75rem; flex-shrink: 0;">
                                                ${escapeHtml((possessor.name || 'Unknown').charAt(0).toUpperCase())}
                                            </div>
                                            <div style="flex: 1;">
                                                <div style="color: #fff; font-weight: 600; font-size: 0.875rem;">
                                                    ${escapeHtml(possessor.name || 'Unknown Player')}
                                                </div>
                                                <div style="color: #71717a; font-size: 0.75rem;">
                                                    ID: ${possessor.serverId || 'N/A'}
                                                </div>
                                            </div>
                                        </div>
                                    `).join('')}
                                </div>
                            </div>
                        ` : `
                            <div style="color: #71717a; font-size: 0.8125rem; display: flex; align-items: center; gap: 0.5rem; padding: 0.5rem; background: rgba(113, 113, 122, 0.05); border-radius: 6px;">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                    <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path>
                                </svg>
                                Not currently in possession
                            </div>
                        `}
                    </div>
                `;
            });
            html += '</div>';
        }
        html += '</div>';
        tabContent.innerHTML = html;
    }

    function renderMemberTerritoryTab(content) {
        const territories = content.territories || content.items || [];
        if (territories.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No territory claimed by your faction yet.</span></div>';
            return;
        }
        let html = '<div class="list-container" style="display:flex;flex-direction:column;gap:0.75rem;">';
        territories.forEach(function(terr) {
            const typeLabel = { turf: 'Turf', stash: 'Stash', shop: 'Shop', corner: 'Corner', trap_house: 'Trap House' }[terr.type] || terr.type || 'Unknown';
            const nearby = (terr.nearby_factions || []).map(function(nb) { return nb.faction && nb.faction.label; }).filter(Boolean);
            const nearbyHtml = nearby.length > 0
                ? `<span style="color:#f59e0b;">⚠ Nearby: ${escapeHtml(nearby.join(', '))}</span>`
                : '<span style="color:#71717a;">No nearby rival territory</span>';
            html += `
                <div style="background:#18181b;border:1px solid #27272a;border-radius:8px;padding:14px 16px;">
                    <div style="font-weight:600;color:#fff;font-size:1rem;margin-bottom:6px;">${escapeHtml(terr.name || 'Unnamed')}</div>
                    <div style="display:flex;flex-wrap:wrap;gap:10px;font-size:0.8rem;color:#a1a1aa;">
                        <span>Type: <strong style="color:#e4e4e7;">${escapeHtml(typeLabel)}</strong></span>
                        <span>Radius: <strong style="color:#e4e4e7;">${terr.radius || 50}m</strong></span>
                        <span>Coords: <strong style="color:#e4e4e7;">${parseFloat(terr.x||0).toFixed(1)}, ${parseFloat(terr.y||0).toFixed(1)}, ${parseFloat(terr.z||0).toFixed(1)}</strong></span>
                    </div>
                    <div style="margin-top:6px;font-size:0.78rem;">${nearbyHtml}</div>
                </div>`;
        });
        html += '</div>';
        tabContent.innerHTML = html;
    }

    function renderAdminTerritoryTab(content) {
        if (content.step === 'select_faction') {
            const factions = content.factions || [];
            if (factions.length === 0) {
                tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No factions available</span></div>';
                return;
            }
            
            let html = '<div class="ck-container"><div class="section-header"><h3>Select Faction for Territory Assignment</h3><p class="section-subtitle">Choose a faction to assign territory to</p></div><div class="faction-list grid-layout">';
            factions.forEach(faction => {
                const initials = (faction.label || faction.name).substring(0, 2).toUpperCase();
                const hue = ((faction.id * 13) % 360);
                const color = `hsl(${hue}, 70%, 60%)`;
                const colorLight = `hsl(${hue}, 70%, 65%)`;
                html += `<div class="faction-item-modern" data-faction-id="${faction.id}" data-faction-label="${escapeHtml(faction.label || faction.name)}">
                    <div class="faction-item-body">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <div class="faction-color-bubble" style="background: ${color};"></div>
                            <div style="flex: 1;">
                                <div class="faction-name-modern">${escapeHtml(faction.label || faction.name)}</div>
                                <div class="faction-description-modern">
                                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display: inline-block; vertical-align: middle; margin-right: 6px; opacity: 0.6;">
                                        <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
                                        <circle cx="12" cy="10" r="3"></circle>
                                    </svg>
                                    Assign territory to this faction
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="faction-item-footer">
                        <button class="btn-select-modern" data-faction-id="${faction.id}" data-faction-label="${escapeHtml(faction.label || faction.name)}" style="--btn-color: ${color}; --btn-color-light: ${colorLight};">
                            <span>Select</span>
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-left: 8px;">
                                <path d="M5 12h14M12 5l7 7-7 7"></path>
                            </svg>
                        </button>
                    </div>
                </div>`;
            });
            html += '</div></div>';
            tabContent.innerHTML = html;
            
            // Attach event listeners for faction selection
            tabContent.querySelectorAll('.btn-select-modern, .faction-item-modern').forEach(item => {
                item.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const factionId = this.getAttribute('data-faction-id') || this.closest('.faction-item-modern')?.getAttribute('data-faction-id');
                    const factionLabel = this.getAttribute('data-faction-label') || this.closest('.faction-item-modern')?.getAttribute('data-faction-label');
                    if (factionId) {
                        post('adminSelectTerritoryFaction', { factionId: parseInt(factionId), factionLabel: factionLabel });
                    }
                });
            });
        } else if (content.step === 'assign_territory') {
            const factionLabel = content.factionLabel || 'Unknown';
            tabContent.innerHTML = `
                <div class="report-container">
                    <h3>Assign Territory - ${escapeHtml(factionLabel)}</h3>
                    <div class="form-group">
                        <label for="territory-name">Territory Name:</label>
                        <input type="text" id="territory-name" class="form-select" placeholder="e.g. Grove Street" required>
                    </div>
                    <div class="form-group">
                        <label for="territory-type">Territory Type:</label>
                        <div class="form-select-wrapper">
                            <select id="territory-type" class="form-select">
                                <option value="turf">Turf</option>
                                <option value="stash">Stash</option>
                                <option value="shop">Shop</option>
                            </select>
                        </div>
                    </div>
                    <div class="form-group" style="margin-bottom:8px;">
                        <button type="button" id="btn-use-position" class="btn-secondary" style="width:100%;padding:10px;background:#27272a;border:1px solid #3f3f46;border-radius:6px;color:#a1a1aa;cursor:pointer;font-size:0.85rem;transition:background 0.15s;">
                            📍 Use Current Position
                        </button>
                    </div>
                    <div class="form-group">
                        <label for="coord-x">X Coordinate:</label>
                        <input type="number" id="coord-x" class="form-select" placeholder="X coordinate" step="0.01" required>
                    </div>
                    <div class="form-group">
                        <label for="coord-y">Y Coordinate:</label>
                        <input type="number" id="coord-y" class="form-select" placeholder="Y coordinate" step="0.01" required>
                    </div>
                    <div class="form-group">
                        <label for="coord-z">Z Coordinate:</label>
                        <input type="number" id="coord-z" class="form-select" placeholder="Z coordinate" step="0.01" required>
                    </div>
                    <div class="form-group">
                        <label for="radius">Radius (meters):</label>
                        <input type="number" id="radius" class="form-select" placeholder="50.0" step="0.1" value="50.0">
                    </div>
                    <div class="form-group">
                        <label for="stash-id">Stash ID (optional):</label>
                        <input type="text" id="stash-id" class="form-select" placeholder="Leave empty if not applicable">
                    </div>
                    <div class="form-actions">
                        <button class="btn-submit" id="btn-submit-territory">Assign Territory</button>
                        <button class="btn-cancel" data-action="territoryCancel">Cancel</button>
                    </div>
                </div>
            `;
            
            const posBtn = tabContent.querySelector('#btn-use-position');
            if (posBtn) {
                posBtn.addEventListener('click', function() {
                    posBtn.textContent = '⌛ Fetching...';
                    postWithData('getPlayerCoords', {}).then(function(data) {
                        if (data && data.x !== undefined) {
                            tabContent.querySelector('#coord-x').value = parseFloat(data.x).toFixed(4);
                            tabContent.querySelector('#coord-y').value = parseFloat(data.y).toFixed(4);
                            tabContent.querySelector('#coord-z').value = parseFloat(data.z).toFixed(4);
                            posBtn.textContent = '✅ Position Set';
                            setTimeout(() => { posBtn.textContent = '📍 Use Current Position'; }, 2000);
                        } else {
                            posBtn.textContent = '❌ Failed';
                            setTimeout(() => { posBtn.textContent = '📍 Use Current Position'; }, 2000);
                        }
                    });
                });
            }

            const submitBtn = tabContent.querySelector('#btn-submit-territory');
            const cancelBtn = tabContent.querySelector('.btn-cancel[data-action="territoryCancel"]');
            if (submitBtn) {
                submitBtn.addEventListener('click', function() {
                    const name = tabContent.querySelector('#territory-name').value.trim();
                    const type = tabContent.querySelector('#territory-type').value;
                    const x = parseFloat(tabContent.querySelector('#coord-x').value);
                    const y = parseFloat(tabContent.querySelector('#coord-y').value);
                    const z = parseFloat(tabContent.querySelector('#coord-z').value);
                    const radius = parseFloat(tabContent.querySelector('#radius').value) || 50.0;
                    const stashId = tabContent.querySelector('#stash-id').value.trim() || null;
                    
                    if (!name || isNaN(x) || isNaN(y) || isNaN(z)) {
                        showToast('Please fill in the name and valid X, Y, Z coordinates', 'warning');
                        return;
                    }
                    
                    post('adminSubmitTerritory', {
                        factionId: content.factionId,
                        territoryData: {
                            name: name,
                            type: type,
                            x: x,
                            y: y,
                            z: z,
                            radius: radius,
                            stashId: stashId
                        }
                    });
                });
            }
            if (cancelBtn) {
                cancelBtn.addEventListener('click', function() {
                    if (content.factionId) {
                        post('adminSelectTerritoryFaction', { factionId: content.factionId, factionLabel: content.factionLabel });
                    } else {
                        post('requestTabData', { tab: 'territory', isAdmin: true });
                    }
                });
            }
        } else if (content.step === 'manage_territories') {
            const territories = content.territories || [];
            const fLabel = escapeHtml(content.factionLabel || 'Unknown');
            let html = `
                <div class="report-container">
                    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px;">
                        <h3 style="margin:0;">Territory — ${fLabel}</h3>
                        <div style="display:flex;gap:8px;">
                            <button class="btn-submit" id="btn-add-territory" style="padding:8px 14px;font-size:0.82rem;">+ Add Territory</button>
                            <button class="btn-cancel" id="btn-back-factions" style="padding:8px 14px;font-size:0.82rem;">← Back</button>
                        </div>
                    </div>`;
            if (territories.length === 0) {
                html += '<div class="empty-state"><span class="empty-text">No territories assigned to this faction.</span></div>';
            } else {
                html += '<div style="display:flex;flex-direction:column;gap:0.6rem;">';
                territories.forEach(function(terr) {
                    const typeLabel = { turf: 'Turf', stash: 'Stash', shop: 'Shop', corner: 'Corner', trap_house: 'Trap House' }[terr.type] || terr.type || 'Unknown';
                    html += `
                        <div style="background:#18181b;border:1px solid #27272a;border-radius:8px;padding:12px 14px;display:flex;align-items:center;justify-content:space-between;">
                            <div>
                                <div style="font-weight:600;color:#fff;margin-bottom:4px;">${escapeHtml(terr.name || 'Unnamed')}</div>
                                <div style="font-size:0.78rem;color:#a1a1aa;">
                                    ${escapeHtml(typeLabel)} &bull;
                                    Radius: ${terr.radius || 50}m &bull;
                                    ${parseFloat(terr.x||0).toFixed(1)}, ${parseFloat(terr.y||0).toFixed(1)}, ${parseFloat(terr.z||0).toFixed(1)}
                                </div>
                            </div>
                            <button class="btn-cancel" data-terr-id="${terr.id}" style="padding:6px 12px;font-size:0.78rem;background:#7f1d1d;border-color:#991b1b;">Delete</button>
                        </div>`;
                });
                html += '</div>';
            }
            html += '</div>';
            tabContent.innerHTML = html;

            const addBtn = tabContent.querySelector('#btn-add-territory');
            if (addBtn) {
                addBtn.addEventListener('click', function() {
                    post('adminAddTerritory', { factionId: content.factionId, factionLabel: content.factionLabel });
                });
            }
            const backBtn = tabContent.querySelector('#btn-back-factions');
            if (backBtn) {
                backBtn.addEventListener('click', function() {
                    post('requestTabData', { tab: 'territory', isAdmin: true });
                });
            }
            tabContent.querySelectorAll('[data-terr-id]').forEach(function(btn) {
                btn.addEventListener('click', function() {
                    const tid = parseInt(this.getAttribute('data-terr-id'));
                    if (tid) {
                        post('adminDeleteTerritory', { territoryId: tid, factionId: content.factionId });
                    }
                });
            });
        }
    }

    // Admin tab rendering functions
    let currentFactionPage = 1;
    const factionsPerPage = 10;

    function renderAdminOverview(content) {
        // Static button is in HTML - only render factions list
        const factions = content.factions || [];
        currentFactionPage = 1; // Reset to first page when refreshing
        
        let html = '<div class="overview-content" style="width: 100%;">';
        
        // All Registered Factions Section (no button - it's static in HTML)
        html += '<div class="info-card" style="margin-bottom: 20px;">';
        html += '<h3 style="margin-bottom: 16px; color: #fff; font-size: 1.125rem; font-weight: 600;">All Registered Factions</h3>';
        
        if (factions.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No factions registered</span></div>';
        } else {
            // Calculate pagination
            const totalPages = Math.ceil(factions.length / factionsPerPage);
            const startIndex = (currentFactionPage - 1) * factionsPerPage;
            const endIndex = startIndex + factionsPerPage;
            const currentFactions = factions.slice(startIndex, endIndex);
            
            html += '<div class="factions-list">';
            currentFactions.forEach(faction => {
                const hue = ((faction.id * 13) % 360);
                const color = `hsl(${hue}, 70%, 55%)`;
                const initial = (faction.label || faction.name || 'F').charAt(0).toUpperCase();
                
                html += `
                    <div class="faction-list-item">
                        <div style="display: flex; align-items: center; gap: 14px; margin-bottom: 12px;">
                            <div class="faction-icon-small" style="background: ${color};">
                                ${escapeHtml(initial)}
                            </div>
                            <div class="faction-list-info" style="flex: 1;">
                                <strong>${escapeHtml(faction.label || faction.name)}</strong>
                                <small>${escapeHtml(faction.name || '')} • ${escapeHtml(faction.type || 'Unknown')}</small>
                            </div>
                        </div>
                        <div class="faction-list-stats">
                            <span class="stat-badge">${faction.member_count || 0} Members</span>
                            <span class="stat-badge">${faction.reputation || 0} Rep</span>
                            <span class="stat-badge">${faction.active_wars || 0}/${faction.max_wars || 2} Wars</span>
                        </div>
                    </div>
                `;
            });
            html += '</div>';
            
            // Pagination controls
            if (totalPages > 1) {
                html += '<div class="pagination-controls">';
                html += `<button class="pagination-btn" ${currentFactionPage === 1 ? 'disabled' : ''} data-page="prev">Previous</button>`;
                html += `<span class="pagination-info">Page ${currentFactionPage} of ${totalPages}</span>`;
                html += `<button class="pagination-btn" ${currentFactionPage === totalPages ? 'disabled' : ''} data-page="next">Next</button>`;
                html += '</div>';
            }
        }
        
        html += '</div>';
        html += '</div>';
        
        tabContent.innerHTML = html;
        
        // Attach pagination event listeners
        if (factions.length > 0 && Math.ceil(factions.length / factionsPerPage) > 1) {
            tabContent.querySelectorAll('.pagination-btn').forEach(btn => {
                btn.addEventListener('click', function() {
                    if (this.disabled) return;
                    const action = this.getAttribute('data-page');
                    if (action === 'prev' && currentFactionPage > 1) {
                        currentFactionPage--;
                    } else if (action === 'next' && currentFactionPage < Math.ceil(factions.length / factionsPerPage)) {
                        currentFactionPage++;
                    }
                    // Re-render with new page
                    renderAdminOverview(content);
                });
            });
        }
    }

    function renderAdminFactionsTab(content) {
        const factions = content.factions || [];
        if (factions.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No factions found</span></div>';
            return;
        }
        
        let html = '<div class="faction-management-list">';
        factions.forEach(faction => {
            const hue = ((faction.id * 13) % 360);
            const color = `hsl(${hue}, 70%, 55%)`;
            const initial = (faction.label || faction.name || 'F').charAt(0).toUpperCase();
            
            html += `
                <div class="faction-management-item" data-faction-id="${faction.id}">
                    <div class="faction-management-header">
                        <div class="faction-icon-small" style="background: ${color};">
                            ${escapeHtml(initial)}
                        </div>
                        <div class="faction-management-info">
                            <div class="faction-management-name">${escapeHtml(faction.label || faction.name)}</div>
                            <div class="faction-management-meta">${escapeHtml(faction.name || '')} • ${escapeHtml(faction.type || 'Unknown')}</div>
                        </div>
                    </div>
                    <div class="faction-management-stats">
                        <div class="stat-item">
                            <span class="stat-label">Members</span>
                            <span class="stat-value">${faction.member_count || 0}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Reputation</span>
                            <span class="stat-value">${faction.reputation || 0}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Wars</span>
                            <span class="stat-value">${faction.active_wars || 0}/${faction.max_wars || 2}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Gun Drop</span>
                            <span class="stat-value">${faction.gun_drop_eligible ? 'Yes' : 'No'}</span>
                        </div>
                    </div>
                    <div class="faction-management-actions">
                        <button class="btn-action btn-edit" data-faction-id="${faction.id}" data-action="edit" title="Edit Faction">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
                                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
                            </svg>
                            Edit
                        </button>
                        <button class="btn-action btn-invite" data-faction-id="${faction.id}" data-action="invite" title="Invite Member">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                                <circle cx="8.5" cy="7" r="4"></circle>
                                <line x1="20" y1="8" x2="20" y2="14"></line>
                                <line x1="23" y1="11" x2="17" y2="11"></line>
                            </svg>
                            Invite
                        </button>
                        <button class="btn-action btn-members" data-faction-id="${faction.id}" data-action="members" title="View Members">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path>
                                <circle cx="9" cy="7" r="4"></circle>
                                <path d="M23 21v-2a4 4 0 0 0-3-3.87"></path>
                                <path d="M16 3.13a4 4 0 0 1 0 7.75"></path>
                            </svg>
                            Members
                        </button>
                        <button class="btn-action btn-delete" data-faction-id="${faction.id}" data-action="delete" title="Delete Faction">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <polyline points="3 6 5 6 21 6"></polyline>
                                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                            </svg>
                            Delete
                        </button>
                    </div>
                </div>
            `;
        });
        html += '</div>';
        tabContent.innerHTML = html;
        
        // Attach event listeners for action buttons
        tabContent.querySelectorAll('.btn-action').forEach(btn => {
            btn.addEventListener('click', function(e) {
                e.stopPropagation();
                const factionId = parseInt(this.getAttribute('data-faction-id'));
                const action = this.getAttribute('data-action');
                const faction = factions.find(f => f.id === factionId);
                
                if (action === 'edit') {
                    showEditFactionDialog(faction);
                } else if (action === 'invite') {
                    showInviteMemberDialog(faction);
                } else if (action === 'members') {
                    showFactionMembers(faction);
                } else if (action === 'delete') {
                    post('adminDeleteFaction', { factionId: factionId });
                }
            });
        });
    }
    
    function showEditFactionDialog(faction) {
        const html = `
            <div class="modal-overlay" id="edit-faction-modal">
                <div class="modal-content">
                    <div class="modal-header">
                        <h3>Edit Faction: ${escapeHtml(faction.label || faction.name)}</h3>
                        <button class="modal-close" id="close-edit-modal">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Faction Name (ID)</label>
                            <input type="text" id="edit-faction-name" value="${escapeHtml(faction.name || '')}" class="form-input" placeholder="e.g. ballas">
                        </div>
                        <div class="form-group">
                            <label>Faction Label (Display Name)</label>
                            <input type="text" id="edit-faction-label" value="${escapeHtml(faction.label || '')}" class="form-input" placeholder="e.g. Ballas">
                        </div>
                        <div class="form-group">
                            <label>Faction Type</label>
                            <select id="edit-faction-type" class="form-select">
                                <option value="gang" ${faction.type === 'gang' ? 'selected' : ''}>Gang</option>
                                <option value="mafia" ${faction.type === 'mafia' ? 'selected' : ''}>Mafia</option>
                                <option value="cartel" ${faction.type === 'cartel' ? 'selected' : ''}>Cartel</option>
                                <option value="organization" ${faction.type === 'organization' ? 'selected' : ''}>Organization</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Reputation</label>
                            <input type="number" id="edit-faction-reputation" value="${faction.reputation || 0}" class="form-input">
                        </div>
                        <div class="form-group">
                            <label>
                                <input type="checkbox" id="edit-faction-gun-drop" ${faction.gun_drop_eligible ? 'checked' : ''}>
                                Gun Drop Eligible
                            </label>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-cancel" id="cancel-edit-faction">Cancel</button>
                        <button class="btn-submit" id="save-edit-faction" data-faction-id="${faction.id}">Save Changes</button>
                    </div>
                </div>
            </div>
        `;
        document.body.insertAdjacentHTML('beforeend', html);
        
        const modal = document.getElementById('edit-faction-modal');
        const closeBtn = document.getElementById('close-edit-modal');
        const cancelBtn = document.getElementById('cancel-edit-faction');
        const saveBtn = document.getElementById('save-edit-faction');
        
        const closeModal = () => {
            if (modal) modal.remove();
        };
        
        closeBtn?.addEventListener('click', closeModal);
        cancelBtn?.addEventListener('click', closeModal);
        modal?.addEventListener('click', function(e) {
            if (e.target === modal) closeModal();
        });
        
        saveBtn?.addEventListener('click', function() {
            const updates = {
                name: document.getElementById('edit-faction-name').value.trim(),
                label: document.getElementById('edit-faction-label').value.trim(),
                type: document.getElementById('edit-faction-type').value,
                reputation: parseInt(document.getElementById('edit-faction-reputation').value) || 0,
                gun_drop_eligible: document.getElementById('edit-faction-gun-drop').checked
            };
            post('adminUpdateFaction', { factionId: parseInt(this.getAttribute('data-faction-id')), updates: updates });
            closeModal();
        });
    }
    
    function showInviteMemberDialog(faction) {
        const html = `
            <div class="modal-overlay" id="invite-member-modal">
                <div class="modal-content">
                    <div class="modal-header">
                        <h3>Invite Member to ${escapeHtml(faction.label || faction.name)}</h3>
                        <button class="modal-close" id="close-invite-modal">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Player Identifier or Server ID</label>
                            <input type="text" id="invite-player-input" class="form-input" placeholder="char1:xxx or Server ID">
                        </div>
                        <div class="form-group">
                            <label>Rank</label>
                            <select id="invite-rank" class="form-select">
                                <option value="runner">Runner</option>
                                <option value="member">Member</option>
                                <option value="shot_caller">Shot Caller</option>
                                <option value="big_homie">Big Homie</option>
                                <option value="boss">Boss</option>
                            </select>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-cancel" id="cancel-invite-member">Cancel</button>
                        <button class="btn-submit" id="submit-invite-member" data-faction-id="${faction.id}">Send Invite</button>
                    </div>
                </div>
            </div>
        `;
        document.body.insertAdjacentHTML('beforeend', html);
        
        const modal = document.getElementById('invite-member-modal');
        const closeBtn = document.getElementById('close-invite-modal');
        const cancelBtn = document.getElementById('cancel-invite-member');
        const submitBtn = document.getElementById('submit-invite-member');
        
        const closeModal = () => {
            if (modal) modal.remove();
        };
        
        closeBtn?.addEventListener('click', closeModal);
        cancelBtn?.addEventListener('click', closeModal);
        modal?.addEventListener('click', function(e) {
            if (e.target === modal) closeModal();
        });
        
        submitBtn?.addEventListener('click', function() {
            const rawInput = document.getElementById('invite-player-input').value;
            const playerInput = (typeof rawInput === 'string' ? rawInput : '').trim().substring(0, 60);
            const allowedRanks = { runner: true, member: true, shot_caller: true, big_homie: true, boss: true };
            const rankSelect = document.getElementById('invite-rank');
            const rank = (rankSelect && allowedRanks[rankSelect.value]) ? rankSelect.value : 'runner';
            const fid = parseInt(this.getAttribute('data-faction-id'), 10);
            if (playerInput && !isNaN(fid) && fid > 0) {
                post('adminInviteMember', {
                    factionId: fid,
                    targetIdentifierOrServerId: playerInput,
                    rank: rank
                });
                closeModal();
                if (currentTab === 'members') {
                    post('requestTabData', { tab: 'members', isAdmin: isAdminMode });
                }
            }
        });
    }
    
    function showFactionMembers(faction) {
        // Request members for this faction
        post('adminGetFactionMembers', { factionId: faction.id });
        // Switch to members tab to show the results
        switchTab('members');
    }

    let currentReportPage = 1;
    const reportsPerPage = 15;

    function renderAdminReportsTab(content) {
        const reports = content.items || [];
        currentReportPage = 1; // Reset to first page when refreshing
        
        if (reports.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No reports found</span></div>';
            return;
        }
        
        // Calculate pagination
        const totalPages = Math.ceil(reports.length / reportsPerPage);
        const startIndex = (currentReportPage - 1) * reportsPerPage;
        const endIndex = startIndex + reportsPerPage;
        const currentReports = reports.slice(startIndex, endIndex);
        
        let html = '<div class="reports-list-container">';
        currentReports.forEach(report => {
            const targetText = report.target_faction_label ? ` → ${escapeHtml(report.target_faction_label)}` : '';
            const status = report.status || 'pending';
            const isHandled = status === 'approved' || status === 'rejected';
            const isPending = status === 'pending';
            const statusColor = status === 'approved' ? '#10b981' : status === 'rejected' ? '#ef4444' : '#f59e0b';
            const date = report.created_at ? (typeof report.created_at === 'string' ? report.created_at.substring(0, 10) : 'Recent') : 'Unknown';
            
            html += `
                <div class="report-card">
                    <div class="report-card-header">
                        <div class="report-card-title">
                            <strong>${escapeHtml(report.faction_label || 'Unknown')}${targetText}</strong>
                            <span class="report-status-badge" style="background: ${statusColor};">
                                ${escapeHtml(status)}
                            </span>
                        </div>
                    </div>
                    <div class="report-card-body">
                        <div class="report-meta-info">
                            <span class="report-meta-item">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 4px;">
                                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                                    <circle cx="12" cy="7" r="4"></circle>
                                </svg>
                                ${escapeHtml(report.reporter_name || 'Unknown')}
                            </span>
                            <span class="report-meta-item">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 4px;">
                                    <circle cx="12" cy="12" r="10"></circle>
                                    <polyline points="12 6 12 12 16 14"></polyline>
                                </svg>
                                ${escapeHtml(date)}
                            </span>
                            <span class="report-meta-item">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 4px;">
                                    <path d="M9 11l3 3L22 4"></path>
                                    <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"></path>
                                </svg>
                                ${escapeHtml(report.report_type || 'Unknown')}
                            </span>
                        </div>
                        <div class="report-details-text">
                            <p>${escapeHtml(report.details || 'No details provided')}</p>
                        </div>
                    </div>
                    <div class="report-card-actions">
                        ${isPending ? `
                            <button class="btn-report-action btn-accept" data-report-id="${report.id}" data-action="approve" title="Approve Report">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <polyline points="20 6 9 17 4 12"></polyline>
                                </svg>
                                Accept
                            </button>
                            <button class="btn-report-action btn-deny" data-report-id="${report.id}" data-action="reject" title="Deny Report">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <line x1="18" y1="6" x2="6" y2="18"></line>
                                    <line x1="6" y1="6" x2="18" y2="18"></line>
                                </svg>
                                Deny
                            </button>
                        ` : `
                            <span class="report-handled-message" style="color: ${statusColor}; font-weight: 600; font-size: 13px;">
                                ${status === 'approved' ? '✓ Report Approved' : '✗ Report Rejected'}
                            </span>
                            <button class="btn-report-action btn-delete" data-report-id="${report.id}" data-action="delete" title="Delete Report">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <polyline points="3 6 5 6 21 6"></polyline>
                                    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                                </svg>
                                Delete
                            </button>
                        `}
                    </div>
                </div>
            `;
        });
        html += '</div>';
        
        // Pagination controls
        if (totalPages > 1) {
            html += '<div class="pagination-controls">';
            html += `<button class="pagination-btn" ${currentReportPage === 1 ? 'disabled' : ''} data-page="prev">Previous</button>`;
            html += `<span class="pagination-info">Page ${currentReportPage} of ${totalPages} (${reports.length} total)</span>`;
            html += `<button class="pagination-btn" ${currentReportPage === totalPages ? 'disabled' : ''} data-page="next">Next</button>`;
            html += '</div>';
        }
        
        tabContent.innerHTML = html;
        
        // Attach event listeners for action buttons
        tabContent.querySelectorAll('.btn-report-action').forEach(btn => {
            btn.addEventListener('click', function(e) {
                e.stopPropagation();
                const reportId = parseInt(this.getAttribute('data-report-id'));
                const action = this.getAttribute('data-action');
                
                if (action === 'approve') {
                    post('adminConfirmApproveReport', { reportId: reportId });
                } else if (action === 'reject') {
                    post('adminConfirmRejectReport', { reportId: reportId });
                } else if (action === 'delete') {
                    post('adminConfirmDeleteReport', { reportId: reportId });
                }
            });
        });
        
        // Attach pagination event listeners
        if (totalPages > 1) {
            tabContent.querySelectorAll('.pagination-btn').forEach(btn => {
                btn.addEventListener('click', function() {
                    if (this.disabled) return;
                    const action = this.getAttribute('data-page');
                    if (action === 'prev' && currentReportPage > 1) {
                        currentReportPage--;
                    } else if (action === 'next' && currentReportPage < totalPages) {
                        currentReportPage++;
                    }
                    // Re-render with new page
                    renderAdminReportsTab(content);
                });
            });
        }
    }

    function renderAdminRulesTab(content) {
        const rules = content.rules || [];
        const factions = content.factions || [];
        
        let html = '<div class="rules-management-container">';
        html += '<div class="rules-header">';
        html += '<h3>Faction Rules Management</h3>';
        html += '<button class="btn-action btn-add-rule" id="btn-add-rule" title="Add New Rule">';
        html += '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">';
        html += '<path d="M12 5v14M5 12h14"></path>';
        html += '</svg>';
        html += 'Add Rule';
        html += '</button>';
        html += '</div>';
        
        if (rules.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No rules found. Click "Add Rule" to create one.</span></div>';
        } else {
            html += '<div class="rules-list">';
            rules.forEach(rule => {
                const factionName = rule.faction_label || (rule.faction_id ? 'Faction #' + rule.faction_id : 'Global');
                html += `
                    <div class="rule-card" data-rule-id="${rule.id}">
                        <div class="rule-card-header">
                            <div class="rule-card-title">
                                <strong>${escapeHtml(rule.rule_title || 'Untitled Rule')}</strong>
                                <span class="rule-badge ${rule.is_global ? 'rule-global' : 'rule-faction'}">
                                    ${rule.is_global ? 'Global' : factionName}
                                </span>
                            </div>
                            <div class="rule-card-actions">
                                <button class="btn-action-small btn-edit-rule" data-rule-id="${rule.id}" title="Edit Rule">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
                                        <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
                                    </svg>
                                </button>
                                <button class="btn-action-small btn-delete-rule" data-rule-id="${rule.id}" title="Delete Rule">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <polyline points="3 6 5 6 21 6"></polyline>
                                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                                    </svg>
                                </button>
                            </div>
                        </div>
                        <div class="rule-card-body">
                            <p>${escapeHtml(rule.rule_content || 'No content')}</p>
                        </div>
                    </div>
                `;
            });
            html += '</div>';
        }
        html += '</div>';
        
        tabContent.innerHTML = html;
        
        // Attach event listeners
        const addBtn = tabContent.querySelector('#btn-add-rule');
        if (addBtn) {
            addBtn.addEventListener('click', function() {
                showAddEditRuleDialog(null, factions);
            });
        }
        
        tabContent.querySelectorAll('.btn-edit-rule').forEach(btn => {
            btn.addEventListener('click', function(e) {
                e.stopPropagation();
                const ruleId = parseInt(this.getAttribute('data-rule-id'));
                const rule = rules.find(r => r.id === ruleId);
                if (rule) {
                    showAddEditRuleDialog(rule, factions);
                }
            });
        });
        
        tabContent.querySelectorAll('.btn-delete-rule').forEach(btn => {
            btn.addEventListener('click', function(e) {
                e.stopPropagation();
                const ruleId = parseInt(this.getAttribute('data-rule-id'));
                if (ruleId) {
                    showConfirm('Are you sure you want to delete this rule?', function() {
                        post('adminDeleteRule', { ruleId: ruleId });
                    });
                }
            });
        });
    }
    
    function renderRulesTab(content) {
        const rules = content.rules || [];
        
        if (rules.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No rules available</span></div>';
            return;
        }
        
        let html = '<div class="rules-view-container">';
        html += '<h3 style="color: #fff; font-size: 20px; font-weight: 700; margin-bottom: 20px;">Faction Rules</h3>';
        html += '<div class="rules-list-view">';
        rules.forEach((rule, index) => {
            html += `
                <div class="rule-view-card">
                    <div class="rule-view-number">${index + 1}</div>
                    <div class="rule-view-content">
                        <h4>${escapeHtml(rule.rule_title || 'Untitled Rule')}</h4>
                        <p>${escapeHtml(rule.rule_content || 'No content')}</p>
                    </div>
                </div>
            `;
        });
        html += '</div>';
        html += '</div>';
        
        tabContent.innerHTML = html;
    }
    
    function showAddEditRuleDialog(rule, factions) {
        const isEdit = rule !== null;
        const html = `
            <div class="modal-overlay" id="rule-modal">
                <div class="modal-content">
                    <div class="modal-header">
                        <h3>${isEdit ? 'Edit Rule' : 'Add New Rule'}</h3>
                        <button class="modal-close" id="close-rule-modal">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Rule Title</label>
                            <input type="text" id="rule-title" class="form-input" value="${isEdit ? escapeHtml(rule.rule_title || '') : ''}" placeholder="e.g. Territory Rules">
                        </div>
                        <div class="form-group">
                            <label>Rule Content</label>
                            <textarea id="rule-content" class="form-textarea" rows="6" placeholder="Enter the rule details...">${isEdit ? escapeHtml(rule.rule_content || '') : ''}</textarea>
                        </div>
                        <div class="form-group">
                            <label>Rule Type</label>
                            <select id="rule-type" class="form-select">
                                <option value="global" ${isEdit && rule.is_global ? 'selected' : ''}>Global (All Factions)</option>
                                <option value="faction" ${isEdit && !rule.is_global ? 'selected' : ''}>Specific Faction</option>
                            </select>
                        </div>
                        <div class="form-group" id="faction-select-group" style="${isEdit && rule.is_global ? 'display: none;' : ''}">
                            <label>Select Faction</label>
                            <select id="rule-faction" class="form-select">
                                <option value="">-- Select Faction --</option>
                                ${factions.map(f => `<option value="${f.id}" ${isEdit && rule.faction_id === f.id ? 'selected' : ''}>${escapeHtml(f.label || f.name)}</option>`).join('')}
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Display Order</label>
                            <input type="number" id="rule-order" class="form-input" value="${isEdit ? (rule.rule_order || 0) : 0}" min="0" placeholder="0">
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-cancel" id="cancel-rule">Cancel</button>
                        <button class="btn-submit" id="save-rule" data-rule-id="${isEdit ? rule.id : ''}">${isEdit ? 'Update Rule' : 'Create Rule'}</button>
                    </div>
                </div>
            </div>
        `;
        document.body.insertAdjacentHTML('beforeend', html);
        
        const modal = document.getElementById('rule-modal');
        const closeBtn = document.getElementById('close-rule-modal');
        const cancelBtn = document.getElementById('cancel-rule');
        const saveBtn = document.getElementById('save-rule');
        const ruleTypeSelect = document.getElementById('rule-type');
        const factionSelectGroup = document.getElementById('faction-select-group');
        
        const closeModal = () => {
            if (modal) modal.remove();
        };
        
        closeBtn?.addEventListener('click', closeModal);
        cancelBtn?.addEventListener('click', closeModal);
        modal?.addEventListener('click', function(e) {
            if (e.target === modal) closeModal();
        });
        
        ruleTypeSelect?.addEventListener('change', function() {
            if (this.value === 'global') {
                factionSelectGroup.style.display = 'none';
                document.getElementById('rule-faction').value = '';
            } else {
                factionSelectGroup.style.display = 'block';
            }
        });
        
        saveBtn?.addEventListener('click', function() {
            const title = document.getElementById('rule-title').value.trim();
            const content = document.getElementById('rule-content').value.trim();
            const ruleType = document.getElementById('rule-type').value;
            const factionId = document.getElementById('rule-faction').value;
            const order = parseInt(document.getElementById('rule-order').value) || 0;
            
            if (!title || !content) {
                showToast('Please fill in both title and content', 'warning');
                return;
            }

            if (ruleType === 'faction' && !factionId) {
                showToast('Please select a faction for this rule', 'warning');
                return;
            }
            
            const ruleData = {
                title: title,
                content: content,
                isGlobal: ruleType === 'global',
                factionId: ruleType === 'faction' ? parseInt(factionId) : null,
                order: order
            };
            
            if (isEdit) {
                ruleData.ruleId = parseInt(this.getAttribute('data-rule-id'));
                post('adminUpdateRule', ruleData);
            } else {
                post('adminCreateRule', ruleData);
            }
            closeModal();
        });
    }

    function renderAdminCKTab(content) {
        const cks = content.items || [];
        if (cks.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No CK requests found</span></div>';
            return;
        }

        const statusColors = { pending: '#f59e0b', approved: '#22c55e', rejected: '#ef4444', executed: '#8b5cf6' };

        let html = '<div class="list-container" style="display:flex;flex-direction:column;gap:0.75rem;">';
        cks.forEach(ck => {
            const sc = statusColors[ck.status] || '#71717a';
            const actionBtns = (function() {
                if (ck.status === 'pending') {
                    return `<button class="btn-ck-action" data-ck-id="${ck.id}" data-action="approved" style="background:#22c55e1a;border:1px solid #22c55e44;color:#22c55e;padding:6px 14px;border-radius:7px;cursor:pointer;font-size:0.8rem;font-weight:600;font-family:inherit;">Approve</button>
                            <button class="btn-ck-action" data-ck-id="${ck.id}" data-action="rejected" style="background:#ef44441a;border:1px solid #ef444444;color:#ef4444;padding:6px 14px;border-radius:7px;cursor:pointer;font-size:0.8rem;font-weight:600;font-family:inherit;">Reject</button>
                            <button class="btn-ck-action" data-ck-id="${ck.id}" data-action="executed" style="background:#8b5cf61a;border:1px solid #8b5cf644;color:#8b5cf6;padding:6px 14px;border-radius:7px;cursor:pointer;font-size:0.8rem;font-weight:600;font-family:inherit;">Execute</button>`;
                } else if (ck.status === 'approved') {
                    return `<button class="btn-ck-action" data-ck-id="${ck.id}" data-action="executed" style="background:#8b5cf61a;border:1px solid #8b5cf644;color:#8b5cf6;padding:6px 14px;border-radius:7px;cursor:pointer;font-size:0.8rem;font-weight:600;font-family:inherit;">Execute</button>
                            <button class="btn-ck-action" data-ck-id="${ck.id}" data-action="rejected" style="background:#ef44441a;border:1px solid #ef444444;color:#ef4444;padding:6px 14px;border-radius:7px;cursor:pointer;font-size:0.8rem;font-weight:600;font-family:inherit;">Reject</button>`;
                }
                return '';
            })();

            html += `
                <div style="background:#27272a;border:1px solid #3f3f46;border-radius:10px;padding:1rem;">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:0.5rem;">
                        <div>
                            <span style="color:#fff;font-weight:600;font-size:0.9375rem;">${escapeHtml(ck.target_name || 'Unknown')}</span>
                            <span style="color:#71717a;font-size:0.875rem;"> — ${escapeHtml(ck.faction_label || 'Unknown Faction')}</span>
                        </div>
                        <span style="background:${sc}1a;color:${sc};border:1px solid ${sc}44;padding:2px 10px;border-radius:6px;font-size:0.7rem;font-weight:700;text-transform:uppercase;white-space:nowrap;">${escapeHtml(ck.status || 'pending')}</span>
                    </div>
                    <div style="color:#a1a1aa;font-size:0.8125rem;margin-bottom:0.5rem;"><strong>Reason:</strong> ${escapeHtml(ck.reason || 'No reason given')}</div>
                    <div style="color:#71717a;font-size:0.75rem;margin-bottom:${actionBtns ? '0.75rem' : '0'};">Submitted: ${formatDate(ck.created_at)}</div>
                    ${actionBtns ? `<div style="display:flex;gap:0.5rem;flex-wrap:wrap;">${actionBtns}</div>` : ''}
                </div>`;
        });
        html += '</div>';
        tabContent.innerHTML = html;

        tabContent.querySelectorAll('.btn-ck-action').forEach(btn => {
            btn.addEventListener('click', function() {
                const ckId = parseInt(this.getAttribute('data-ck-id'));
                const action = this.getAttribute('data-action');
                if (ckId && action) {
                    post('adminUpdateCK', { ckId: ckId, status: action });
                }
            });
        });
    }

    function renderAdminConflictsTab(content) {
        const conflicts = content.conflicts || [];
        const factions = content.factions || [];
        
        let html = `
            <div class="conflicts-admin-container">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
                    <h3 style="color: #fff; font-size: 1.125rem; font-weight: 600;">Conflict Management</h3>
                    <button class="btn-action btn-create-conflict" id="btn-create-conflict" style="padding: 0.5rem 1rem; font-size: 0.875rem;">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 6px; vertical-align: middle;">
                            <path d="M12 5v14M5 12h14"></path>
                        </svg>
                        Create Conflict
                    </button>
                </div>
        `;
        
        if (conflicts.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No conflicts found</span></div>';
        } else {
            html += '<div class="conflicts-list">';
            conflicts.forEach(conflict => {
                const statusClass = conflict.status === 'active' ? 'status-active' : 'status-ended';
                const statusText = conflict.status === 'active' ? 'Active' : 'Ended';
                const statusColor = conflict.status === 'active' ? '#ef4444' : '#71717a';
                
                html += `
                    <div class="conflict-card" data-conflict-id="${conflict.id}">
                        <div style="display: flex; align-items: center; gap: 1rem; flex: 1;">
                            <div style="flex: 1;">
                                <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem;">
                                    <span class="conflict-status ${statusClass}" style="background: ${statusColor}; padding: 0.25rem 0.75rem; border-radius: 6px; font-size: 0.75rem; font-weight: 600; color: #fff;">
                                        ${statusText}
                                    </span>
                                    <span style="color: #71717a; font-size: 0.8125rem;">${conflict.type || 'war'}</span>
                                </div>
                                <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem;">
                                    ${escapeHtml(conflict.faction1_label || 'Unknown')} <span style="color: #71717a;">vs</span> ${escapeHtml(conflict.faction2_label || 'Unknown')}
                                </div>
                                ${conflict.reason ? `<div style="color: #a1a1aa; font-size: 0.8125rem; margin-top: 0.25rem;">${escapeHtml(conflict.reason)}</div>` : ''}
                                <div style="color: #71717a; font-size: 0.75rem; margin-top: 0.5rem;">
                                    Started: ${formatDate(conflict.started_at)}
                                </div>
                            </div>
                        </div>
                        <div class="conflict-actions">
                            <button class="btn-action-small btn-toggle-conflict" 
                                    data-conflict-id="${conflict.id}" 
                                    data-current-status="${conflict.status}"
                                    title="${conflict.status === 'active' ? 'Deactivate' : 'Activate'}">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    ${conflict.status === 'active' ? 
                                        '<path d="M18 6L6 18M6 6l12 12"></path>' : 
                                        '<path d="M20 6L9 17l-5-5"></path>'
                                    }
                                </svg>
                            </button>
                        </div>
                    </div>
                `;
            });
            html += '</div>';
        }
        
        html += '</div>';
        tabContent.innerHTML = html;
        
        // Attach event listeners
        const createBtn = tabContent.querySelector('#btn-create-conflict');
        if (createBtn) {
            createBtn.addEventListener('click', function() {
                showCreateConflictDialog(factions);
            });
        }
        
        tabContent.querySelectorAll('.btn-toggle-conflict').forEach(btn => {
            btn.addEventListener('click', function(e) {
                e.stopPropagation();
                const conflictId = this.getAttribute('data-conflict-id');
                const currentStatus = this.getAttribute('data-current-status');
                const newStatus = currentStatus === 'active' ? 'ended' : 'active';
                const actionText = newStatus === 'active' ? 'activate' : 'deactivate';
                
                // Use ox_lib confirmation dialog instead of JavaScript confirm
                post('adminConfirmConflictStatus', { 
                    conflictId: conflictId, 
                    status: newStatus,
                    actionText: actionText
                });
            });
        });
    }
    
    function showCreateConflictDialog(factions) {
        const html = `
            <div class="modal-overlay" id="create-conflict-modal">
                <div class="modal-content" style="max-width: 500px;">
                    <div class="modal-header">
                        <h3>Create Conflict</h3>
                        <button class="modal-close" id="close-create-conflict-modal">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Faction 1:</label>
                            <select class="form-select" id="conflict-faction1" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem;">
                                <option value="">Select Faction</option>
                                ${factions.map(f => `<option value="${f.id}">${escapeHtml(f.label || f.name)}</option>`).join('')}
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Faction 2:</label>
                            <select class="form-select" id="conflict-faction2" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem;">
                                <option value="">Select Faction</option>
                                ${factions.map(f => `<option value="${f.id}">${escapeHtml(f.label || f.name)}</option>`).join('')}
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Conflict Type:</label>
                            <select class="form-select" id="conflict-type" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem;">
                                <option value="war">War</option>
                                <option value="dispute">Dispute</option>
                                <option value="rivalry">Rivalry</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Reason (optional):</label>
                            <textarea class="form-textarea" id="conflict-reason" rows="3" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem; resize: vertical;"></textarea>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-action" id="submit-create-conflict" style="flex: 1;">Create Conflict</button>
                        <button class="btn-action" id="cancel-create-conflict" style="background: #27272a; flex: 1;">Cancel</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', html);
        const modal = document.getElementById('create-conflict-modal');
        
        const closeModal = () => {
            if (modal) modal.remove();
        };
        
        document.getElementById('close-create-conflict-modal').addEventListener('click', closeModal);
        document.getElementById('cancel-create-conflict').addEventListener('click', closeModal);
        
        document.getElementById('submit-create-conflict').addEventListener('click', function() {
            const faction1Id = document.getElementById('conflict-faction1').value;
            const faction2Id = document.getElementById('conflict-faction2').value;
            const conflictType = document.getElementById('conflict-type').value;
            const reason = document.getElementById('conflict-reason').value;
            
            if (!faction1Id || !faction2Id) {
                showToast('Please select both factions', 'warning');
                return;
            }

            if (faction1Id === faction2Id) {
                showToast('Cannot create a conflict between the same faction', 'error');
                return;
            }
            
            post('adminCreateConflict', {
                faction1Id: faction1Id,
                faction2Id: faction2Id,
                conflictType: conflictType,
                reason: reason
            });
            
            closeModal();
        });
    }
    
    function renderMemberConflictsTab(content) {
        const conflicts = content.conflicts || [];
        const alliances = content.alliances || [];
        
        let html = '<div class="conflicts-member-container">';
        
        if (conflicts.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No active conflicts - You are not currently at war</span></div>';
        } else {
            html += '<div class="conflicts-list">';
            html += '<h3 style="color: #fff; font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">Active Conflicts</h3>';
            
            conflicts.forEach(conflict => {
                // Show both factions in the conflict
                const faction1Label = conflict.faction1_label || 'Unknown';
                const faction2Label = conflict.faction2_label || 'Unknown';
                
                html += `
                    <div class="conflict-card" style="background: #27272a; border: 1px solid #3f3f46; border-radius: 10px; padding: 1rem; margin-bottom: 0.75rem;">
                        <div style="display: flex; align-items: center; gap: 1rem;">
                            <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
                                <div class="faction-icon-small" style="background: #ef4444; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 14px; flex-shrink: 0;">
                                    ${escapeHtml(faction1Label.charAt(0).toUpperCase())}
                                </div>
                                <span style="color: #71717a;">vs</span>
                                <div class="faction-icon-small" style="background: #3b82f6; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 14px; flex-shrink: 0;">
                                    ${escapeHtml(faction2Label.charAt(0).toUpperCase())}
                                </div>
                            </div>
                            <div style="flex: 1;">
                                <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem;">
                                    ${escapeHtml(faction1Label)} <span style="color: #71717a;">vs</span> ${escapeHtml(faction2Label)}
                                </div>
                                <div style="color: #71717a; font-size: 0.8125rem; margin-bottom: 0.25rem;">
                                    Type: ${escapeHtml(conflict.type || 'war')}
                                </div>
                                ${conflict.reason ? `<div style="color: #a1a1aa; font-size: 0.8125rem; margin-top: 0.25rem;">${escapeHtml(conflict.reason)}</div>` : ''}
                                <div style="color: #71717a; font-size: 0.75rem; margin-top: 0.5rem;">
                                    Started: ${formatDate(conflict.started_at)}
                                </div>
                            </div>
                            <span class="conflict-status status-active" style="background: #ef4444; padding: 0.25rem 0.75rem; border-radius: 6px; font-size: 0.75rem; font-weight: 600; color: #fff;">
                                Active
                            </span>
                        </div>
                    </div>
                `;
            });
            
            html += '</div>';
        }
        
        if (alliances.length > 0) {
            html += `
                <div style="margin-top: 2rem;">
                    <h3 style="color: #fff; font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">Alliances</h3>
                    <div style="color: #a1a1aa; font-size: 0.9375rem;">
                        You have ${alliances.length} active alliance(s)
                    </div>
                </div>
            `;
        }
        
        html += '</div>';
        tabContent.innerHTML = html;
    }
    
    function formatDate(dateValue) {
        if (!dateValue) return 'Unknown';
        try {
            // oxmysql may return Unix timestamp (number) or a date string
            const date = (typeof dateValue === 'number')
                ? new Date(dateValue * 1000)   // Unix seconds → ms
                : new Date(dateValue);
            if (isNaN(date.getTime())) return String(dateValue);
            return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } catch (e) {
            return String(dateValue);
        }
    }
    
    function renderAdminCooldownsTab(content) {
        const cooldowns = content.cooldowns || [];
        const factions = content.factions || [];
        
        let html = `
            <div class="cooldowns-admin-container">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
                    <h3 style="color: #fff; font-size: 1.125rem; font-weight: 600;">Cooldown Management</h3>
                    <button class="btn-action btn-create-cooldown" id="btn-create-cooldown" style="padding: 0.5rem 1rem; font-size: 0.875rem;">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right: 6px; vertical-align: middle;">
                            <path d="M12 5v14M5 12h14"></path>
                        </svg>
                        Set Cooldown
                    </button>
                </div>
        `;
        
        if (cooldowns.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No active cooldowns</span></div>';
        } else {
            html += '<div class="cooldowns-list">';
            cooldowns.forEach(cooldown => {
                const secsRemaining = typeof cooldown.seconds_remaining === 'number' ? cooldown.seconds_remaining : 0;
                const timeRemaining = formatTimeRemaining(secsRemaining);
                const typeLabel = getCooldownTypeLabel(cooldown.type);
                const endsAtDisplay = cooldown.ends_at ? formatDate(cooldown.ends_at) : 'Unknown';

                html += `
                    <div class="cooldown-card" data-cooldown-id="${cooldown.id}" style="background: #27272a; border: 1px solid #3f3f46; border-radius: 10px; padding: 1rem; margin-bottom: 0.75rem; display: flex; align-items: center; justify-content: space-between; gap: 1rem;">
                        <div style="display: flex; align-items: center; gap: 1rem; flex: 1;">
                            <div class="faction-icon-small" style="background: #f59e0b; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 14px; flex-shrink: 0;">
                                ${escapeHtml((cooldown.faction_label || 'Unknown').charAt(0).toUpperCase())}
                            </div>
                            <div style="flex: 1;">
                                <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem;">
                                    ${escapeHtml(cooldown.faction_label || 'Unknown Faction')}
                                </div>
                                <div style="color: #71717a; font-size: 0.8125rem; margin-bottom: 0.25rem;">
                                    Type: ${escapeHtml(typeLabel)} | Remaining: <span style="color: #f59e0b; font-weight: 600;">${timeRemaining}</span>
                                </div>
                                <div style="color: #71717a; font-size: 0.75rem; margin-top: 0.5rem;">
                                    Ends: ${endsAtDisplay}
                                </div>
                            </div>
                        </div>
                        <div class="cooldown-actions">
                            <button class="btn-action-small btn-remove-cooldown" 
                                    data-cooldown-id="${cooldown.id}"
                                    title="Remove Cooldown">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <path d="M18 6L6 18M6 6l12 12"></path>
                                </svg>
                            </button>
                        </div>
                    </div>
                `;
            });
            html += '</div>';
        }
        
        html += '</div>';
        tabContent.innerHTML = html;
        
        // Attach event listeners
        const createBtn = tabContent.querySelector('#btn-create-cooldown');
        if (createBtn) {
            createBtn.addEventListener('click', function() {
                showCreateCooldownDialog(factions);
            });
        }
        
        tabContent.querySelectorAll('.btn-remove-cooldown').forEach(btn => {
            btn.addEventListener('click', function(e) {
                e.stopPropagation();
                const cooldownId = this.getAttribute('data-cooldown-id');
                post('adminConfirmRemoveCooldown', { cooldownId: cooldownId });
            });
        });
    }
    
    function showCreateCooldownDialog(factions) {
        const html = `
            <div class="modal-overlay" id="create-cooldown-modal">
                <div class="modal-content" style="max-width: 500px;">
                    <div class="modal-header">
                        <h3>Set Cooldown</h3>
                        <button class="modal-close" id="close-create-cooldown-modal">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Faction:</label>
                            <select class="form-select" id="cooldown-faction" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem;">
                                <option value="">Select Faction</option>
                                ${factions.map(f => `<option value="${f.id}">${escapeHtml(f.label || f.name)}</option>`).join('')}
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Cooldown Type:</label>
                            <select class="form-select" id="cooldown-type" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem;">
                                <option value="war">War</option>
                                <option value="ck">CK Request</option>
                                <option value="territory">Territory Claim</option>
                                <option value="gun_drop">Gun Drop</option>
                                <option value="violation">Violation</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Duration:</label>
                            <select class="form-select" id="cooldown-duration" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem;">
                                <option value="300">5 minutes</option>
                                <option value="900">15 minutes</option>
                                <option value="1800">30 minutes</option>
                                <option value="3600" selected>1 hour</option>
                                <option value="7200">2 hours</option>
                                <option value="14400">4 hours</option>
                                <option value="28800">8 hours</option>
                                <option value="43200">12 hours</option>
                                <option value="86400">24 hours</option>
                                <option value="172800">48 hours</option>
                                <option value="604800">7 days</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Reason (optional):</label>
                            <textarea class="form-textarea" id="cooldown-reason" rows="3" style="width: 100%; padding: 0.75rem; background: #27272a; border: 1px solid #3f3f46; border-radius: 8px; color: #fff; font-size: 0.9375rem; resize: vertical;" placeholder="Reason for this cooldown..."></textarea>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-action" id="submit-create-cooldown" style="flex: 1;">Set Cooldown</button>
                        <button class="btn-action" id="cancel-create-cooldown" style="background: #27272a; flex: 1;">Cancel</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', html);
        const modal = document.getElementById('create-cooldown-modal');
        
        const closeModal = () => {
            if (modal) modal.remove();
        };
        
        document.getElementById('close-create-cooldown-modal').addEventListener('click', closeModal);
        document.getElementById('cancel-create-cooldown').addEventListener('click', closeModal);
        
        document.getElementById('submit-create-cooldown').addEventListener('click', function() {
            const factionId = document.getElementById('cooldown-faction').value;
            const cooldownType = document.getElementById('cooldown-type').value;
            const duration = document.getElementById('cooldown-duration').value;
            const reason = document.getElementById('cooldown-reason').value;
            
            if (!factionId) {
                showToast('Please select a faction', 'warning');
                return;
            }

            if (!cooldownType) {
                showToast('Please select a cooldown type', 'warning');
                return;
            }

            post('adminSetCooldown', {
                factionId: factionId,
                cooldownType: cooldownType,
                durationSeconds: parseInt(duration),
                reason: reason
            });
            
            closeModal();
        });
    }
    
    function renderMemberCooldownsTab(content) {
        const cooldowns = Array.isArray(content.cooldowns) ? content.cooldowns : [];
        const ckHistory = content.ckHistory || [];

        // Clear any existing countdown intervals
        if (window.cooldownIntervals) {
            window.cooldownIntervals.forEach(interval => clearInterval(interval));
        }
        window.cooldownIntervals = [];

        let html = '<div class="cooldowns-member-container">';

        // Display active cooldowns
        if (cooldowns.length === 0) {
            html += '<div class="empty-state"><span class="empty-text">No active cooldowns</span></div>';
        } else {
            html += '<h3 style="color: #fff; font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">Active Cooldowns</h3>';
            html += '<div class="cooldowns-list" id="member-cooldowns-list">';

            cooldowns.forEach(cooldown => {
                const type = cooldown.type || '';
                const secsRemaining = parseInt(cooldown.seconds_remaining, 10) || 0;
                const endsAt = cooldown.ends_at || '';
                const reason = cooldown.reason || '';
                const timeRemaining = formatTimeRemaining(secsRemaining);
                const typeLabel = getCooldownTypeLabel(type);
                const cooldownId = `cooldown-${cooldown.id}`;

                html += `
                    <div class="cooldown-card" id="${cooldownId}" style="background: #27272a; border: 1px solid #3f3f46; border-radius: 10px; padding: 1rem; margin-bottom: 0.75rem;" data-ends-at="${escapeHtml(endsAt)}">
                        <div style="display: flex; align-items: center; gap: 1rem;">
                            <div class="faction-icon-small" style="background: #f59e0b; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; font-size: 14px; flex-shrink: 0;">
                                ${escapeHtml(typeLabel.charAt(0).toUpperCase())}
                            </div>
                            <div style="flex: 1;">
                                <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem;">
                                    ${escapeHtml(typeLabel)} Cooldown
                                </div>
                                ${reason ? `<div style="color: #a1a1aa; font-size: 0.8rem; margin-bottom: 0.25rem;">${escapeHtml(reason)}</div>` : ''}
                                <div style="color: #71717a; font-size: 0.8125rem;">
                                    Time Remaining: <span class="cooldown-timer" style="color: #f59e0b; font-weight: 600;">${timeRemaining}</span>
                                </div>
                            </div>
                            <span class="cooldown-status" style="background: #f59e0b; padding: 0.25rem 0.75rem; border-radius: 6px; font-size: 0.75rem; font-weight: 600; color: #fff;">
                                Active
                            </span>
                        </div>
                    </div>
                `;
            });

            html += '</div>';
        }

        // Display CK History if available
        if (ckHistory.length > 0) {
            html += `
                <div style="margin-top: 2rem;">
                    <h3 style="color: #fff; font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">CK Request History</h3>
                    <div class="cooldowns-list">
            `;

            ckHistory.forEach(ck => {
                const statusColor = ck.status === 'approved' ? '#10b981' : ck.status === 'rejected' ? '#ef4444' : '#f59e0b';
                html += `
                    <div class="cooldown-card" style="background: #27272a; border: 1px solid #3f3f46; border-radius: 10px; padding: 1rem; margin-bottom: 0.75rem;">
                        <div style="color: #fff; font-weight: 600; margin-bottom: 0.25rem;">
                            ${escapeHtml(ck.target_name || 'Unknown')}
                        </div>
                        <div style="color: #71717a; font-size: 0.8125rem; margin-bottom: 0.25rem;">
                            Status: <span style="color: ${statusColor}; font-weight: 600;">${escapeHtml(ck.status || 'pending')}</span>
                        </div>
                        ${ck.reason ? `<div style="color: #a1a1aa; font-size: 0.8125rem; margin-top: 0.25rem;">${escapeHtml(ck.reason)}</div>` : ''}
                        <div style="color: #71717a; font-size: 0.75rem; margin-top: 0.5rem;">
                            ${formatDate(ck.requested_at)}
                        </div>
                    </div>
                `;
            });

            html += '</div></div>';
        }

        html += '</div>';
        tabContent.innerHTML = html;

        // Start live countdown timers for each cooldown
        cooldowns.forEach(cooldown => {
            const cooldownCard = document.getElementById(`cooldown-${cooldown.id}`);
            if (!cooldownCard) return;
            const endsAt = cooldownCard.getAttribute('data-ends-at');
            if (!endsAt) return;
            const timerElement = cooldownCard.querySelector('.cooldown-timer');
            if (!timerElement) return;

            const interval = setInterval(() => {
                try {
                    const diff = Math.max(0, Math.floor((new Date(endsAt) - new Date()) / 1000));
                    if (diff <= 0) {
                        timerElement.textContent = 'Expired';
                        timerElement.style.color = '#ef4444';
                        clearInterval(interval);
                        const idx = window.cooldownIntervals.indexOf(interval);
                        if (idx > -1) window.cooldownIntervals.splice(idx, 1);
                        setTimeout(() => post('requestTabData', { tab: 'cooldowns', isAdmin: false }), 1000);
                    } else {
                        timerElement.textContent = formatTimeRemaining(diff);
                        timerElement.style.color = '#f59e0b';
                    }
                } catch (e) {
                    clearInterval(interval);
                }
            }, 1000);

            window.cooldownIntervals.push(interval);
        });
    }
    
    function getCooldownTypeLabel(type) {
        const labels = {
            'war': 'War',
            'ck': 'CK Request',
            'territory': 'Territory Claim',
            'territory_claim': 'Territory Claim',
            'gun_drop': 'Gun Drop',
            'violation': 'Violation',
            'custom': 'Custom'
        };
        return labels[type] || type;
    }
    
    function calculateTimeRemaining(endsAt) {
        if (!endsAt) return 'Unknown';
        try {
            const endTime = new Date(endsAt);
            const now = new Date();
            const diff = Math.max(0, Math.floor((endTime - now) / 1000)); // seconds
            return formatTimeRemaining(diff);
        } catch (e) {
            return 'Unknown';
        }
    }
    
    function formatTimeRemaining(seconds) {
        if (!seconds || seconds <= 0) return 'Expired';
        
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;
        
        if (days > 0) {
            return `${days}d ${hours}h ${minutes}m`;
        } else if (hours > 0) {
            return `${hours}h ${minutes}m ${secs}s`;
        } else if (minutes > 0) {
            return `${minutes}m ${secs}s`;
        } else {
            return `${secs}s`;
        }
    }
    
    function renderAdminViolationsTab(content) {
        const violations = content.items || [];
        if (violations.length === 0) {
            tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">No violations found</span></div>';
            return;
        }
        
        let html = '<div class="list-container">';
        violations.forEach(violation => {
            const factionLabel = violation.faction_label || 'Unknown Faction';
            const memberName = violation.member_name || violation.reporter_name || 'Unknown';
            const violationType = violation.violation_type || 'Unknown';
            const description = violation.description || 'No description';
            const sourceType = violation.source_type || 'violation';
            const date = formatDate(violation.created_at);
            
            html += `
                <div class="list-item">
                    <strong>${escapeHtml(factionLabel)}</strong> - ${escapeHtml(violationType)}<br>
                    <small>Member: ${escapeHtml(memberName)} | Source: ${escapeHtml(sourceType)} | Date: ${escapeHtml(date)}</small><br>
                    <small>${escapeHtml(description.length > 100 ? description.substring(0, 100) + '...' : description)}</small>
                </div>
            `;
        });
        html += '</div>';
        tabContent.innerHTML = html;
    }

    // Tab button clicks
    tabs.addEventListener('click', function(e) {
        if (e.target.classList.contains('tab-btn')) {
            const tabName = e.target.getAttribute('data-tab');
            if (tabName) {
                switchTab(tabName);
            }
        }
    });

    btnClose.addEventListener('click', close);

    // Static create faction button event listener
    if (btnCreateFactionStatic) {
        btnCreateFactionStatic.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            post('adminCreateFaction', {});
        });
    }

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && !panel.classList.contains('hidden')) close();
    });

    window.addEventListener('message', function (event) {
        const data = event.data;
        
        if (data.action === 'open') {
            currentFaction = (data.factions && data.factions[0]) || null;
            const isAdmin = data.isAdmin || false;

            // Update tabs based on admin or member
            updateTabsForRole(isAdmin);

            if (data.usePhoneUI) {
                openPhoneMode();
            } else {
                if (isPhoneMode) exitPhoneMode();
            }

            panel.classList.remove('hidden');
            switchTab('overview');
        }
        
        if (data.action === 'close') {
            close();
        }
        
        if (data.action === 'updateFactionHUD') {
            // Update faction info inside the Dynamic Island pill (visible only when phone is open)
            const labelEl = document.getElementById('phone-faction-label');
            const rankEl = document.getElementById('phone-faction-rank');
            if (labelEl) labelEl.textContent = data.show ? (data.factionLabel || '') : '';
            if (rankEl) rankEl.textContent = data.show ? (data.rank || '') : '';
        }

        if (data.action === 'hide') {
            // Hide NUI but keep it in memory
            panel.classList.add('hidden');
        }

        if (data.action === 'show') {
            // Show NUI again
            panel.classList.remove('hidden');
        }
        
        if (data.action === 'updateConflictsData') {
            if (currentTab !== 'conflicts' && (currentTab !== 'overview' || isAdminMode)) return;
            const conflicts = data.conflicts || [];
            const alliances = data.alliances || [];
            
            if (currentTab === 'conflicts') {
                // Update conflicts tab
                if (isAdminMode) {
                    renderAdminConflictsTab({ conflicts: conflicts, factions: [] });
                } else {
                    renderMemberConflictsTab({ conflicts: conflicts, alliances: alliances });
                }
            } else if (currentTab === 'overview' && !isAdminMode) {
                // Update overview tab with conflicts (only for members)
                const overviewContent = tabContent.querySelector('.overview-content');
                if (overviewContent) {
                    // Find and update the conflicts section
                    let conflictsSection = overviewContent.querySelector('[data-conflicts-section]');
                    
                    // If conflicts section doesn't exist, create it
                    if (!conflictsSection) {
                        conflictsSection = document.createElement('div');
                        conflictsSection.setAttribute('data-conflicts-section', '');
                        overviewContent.appendChild(conflictsSection);
                    }
                    
                    // Clear existing content
                    conflictsSection.innerHTML = '';
                    
                    // Add new conflicts section only if there are conflicts
                    if (conflicts.length > 0) {
                        const factionLabel = overviewContent.querySelector('h3')?.textContent || '';
                        let conflictsHtml = '<div style="margin-top: 1.5rem;"><h4 style="color: #fff; font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem;">Active Wars:</h4><div style="display: flex; flex-direction: column; gap: 0.5rem;">';
                        conflicts.forEach(conflict => {
                            const otherFaction = conflict.faction1_label === factionLabel ? conflict.faction2_label : conflict.faction1_label;
                            conflictsHtml += `
                                <div style="background: #27272a; border: 1px solid #ef4444; border-radius: 8px; padding: 0.75rem; display: flex; align-items: center; gap: 0.75rem;">
                                    <div style="width: 8px; height: 8px; background: #ef4444; border-radius: 50%; flex-shrink: 0;"></div>
                                    <div style="flex: 1;">
                                        <div style="color: #fff; font-weight: 600; font-size: 0.875rem;">War with ${escapeHtml(otherFaction)}</div>
                                        ${conflict.reason ? `<div style="color: #71717a; font-size: 0.75rem; margin-top: 0.25rem;">${escapeHtml(conflict.reason.length > 60 ? conflict.reason.substring(0, 60) + '...' : conflict.reason)}</div>` : ''}
                                    </div>
                                </div>
                            `;
                        });
                        conflictsHtml += '</div></div>';
                        conflictsSection.innerHTML = conflictsHtml;
                    }
                }
            }
            // If neither conflicts nor overview tab is active, don't update anything
        }
        
        if (data.action === 'updateTab') {
            const tab = data.tab;
            const content = data.content || {};
            if (tab && tab !== currentTab) return;

            if (tab === 'overview') {
                if (isAdminMode) {
                    // Admin overview tab - static button is in HTML, just render factions list
                    renderAdminOverview(content);
                } else if (content.label) {
                    // Member overview tab - only show basic faction info, conflicts will be added separately if needed
                    tabContent.innerHTML = `
                        <div class="overview-content">
                            <div class="info-card">
                                <h3>${escapeHtml(content.label)}</h3>
                                <div class="info-row">
                                    <span class="info-label">Type:</span>
                                    <span class="info-value">${escapeHtml(content.type || 'Unknown')}</span>
                                </div>
                                <div class="info-row">
                                    <span class="info-label">Reputation:</span>
                                    <span class="info-value">${content.reputation || 0}</span>
                                </div>
                                <div class="info-row">
                                    <span class="info-label">Active Wars:</span>
                                    <span class="info-value">${content.active_wars || 0} / ${content.max_wars || 0}</span>
                                </div>
                            </div>
                            <div data-conflicts-section></div>
                        </div>
                    `;
                } else {
                    renderOverview();
                }
            } else if (tab === 'members') {
                if (currentTab !== 'members') return;
                if (content.selectFactionFirst) {
                    tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">' + (content.message || 'Select a faction from Overview and click View Members to view members.') + '</span></div>';
                    return;
                }
                const members = content.members || (content.items && content.items[0] && content.items[0].player_name ? content.items : null);
                const showActions = content.isAdmin || content.isManagement;
                if (members && showActions && content.factionId) {
                    renderMembersList(members, true, content.factionId, content.isManagement);
                } else if (members && !showActions) {
                    renderMembersList(members, false, content.factionId, false);
                } else {
                    renderList(content.items || [], 'No members found');
                }
            } else if (tab === 'weapons') {
                if (isAdminMode) {
                    if (content.step) {
                        renderAdminWeaponTab(content);
                    } else if (content.factions) {
                        // Initial load - show faction selection
                        renderAdminWeaponTab({ step: 'select_faction', factions: content.factions });
                    } else if (content.weapons !== undefined) {
                        // Weapons list received
                        renderAdminWeaponTab(content);
                    } else {
                        tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                    }
                } else {
                    // Member weapons view - render with possession info
                    renderMemberWeaponsTab(content);
                }
            } else if (tab === 'conflicts') {
                // Only render conflicts tab if conflicts tab is actually the current tab
                // This prevents conflicts from rendering when overview is active
                if (currentTab === 'conflicts') {
                    if (isAdminMode) {
                        renderAdminConflictsTab(content);
                    } else {
                        renderMemberConflictsTab(content);
                    }
                }
            } else if (tab === 'cooldowns') {
                if (isAdminMode) {
                    renderAdminCooldownsTab(content);
                } else {
                    renderMemberCooldownsTab(content);
                }
            } else if (tab === 'warnings') {
                renderList(content.items || [], 'No warnings');
            } else if (tab === 'territory') {
                if (isAdminMode) {
                    if (content.step) {
                        renderAdminTerritoryTab(content);
                    } else if (content.factions) {
                        // Initial load - show faction selection
                        renderAdminTerritoryTab({ step: 'select_faction', factions: content.factions });
                    } else {
                        tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                    }
                } else {
                    renderMemberTerritoryTab(content);
                }
            } else if (tab === 'report') {
                renderReportTab(content);
            } else if (tab === 'ck') {
                if (isAdminMode) {
                    if (content.isAdmin || content.items) {
                        renderAdminCKTab(content);
                    } else {
                        tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                    }
                } else {
                    renderCKTab(content);
                }
            } else if (tab === 'violations' && isAdminMode) {
                if (content.items !== undefined) {
                    renderAdminViolationsTab(content);
                } else {
                    tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                }
            } else if (tab === 'factions' && isAdminMode) {
                if (content.factions !== undefined) {
                    renderAdminFactionsTab(content);
                } else {
                    tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                }
            } else if (tab === 'reports' && isAdminMode) {
                if (content.items !== undefined) {
                    renderAdminReportsTab(content);
                } else {
                    tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                }
            } else if (tab === 'rules') {
                if (isAdminMode) {
                    if (content.rules !== undefined) {
                        renderAdminRulesTab(content);
                    } else {
                        tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                    }
                } else {
                    if (content.rules !== undefined) {
                        renderRulesTab(content);
                    } else {
                        tabContent.innerHTML = '<div class="empty-state"><span class="empty-text">Loading...</span></div>';
                    }
                }
            } else if (tab === 'reputation') {
                if (content.reputation !== undefined) {
                    clearCooldownTimers();
                    const cdSecs = parseInt(content.gunDropCooldownSecs) || 0;
                    const cdDisplay = cdSecs > 0 ? formatTimeRemaining(cdSecs) : 'Available Now';
                    const cdColor   = cdSecs > 0 ? '#f59e0b' : '#22c55e';
                    tabContent.innerHTML = `
                        <div class="overview-content">
                            <div class="info-card">
                                <h3>Reputation & Status</h3>
                                <div class="info-row">
                                    <span class="info-label">Faction Reputation:</span>
                                    <span class="info-value">${content.reputation}</span>
                                </div>
                                <div class="info-row">
                                    <span class="info-label">Your Rank:</span>
                                    <span class="info-value">${escapeHtml(content.rank || 'Unknown')}</span>
                                </div>
                                <div class="info-row">
                                    <span class="info-label">Active Wars:</span>
                                    <span class="info-value">${content.activeWars || '0 / 2'}</span>
                                </div>
                                <div class="info-row">
                                    <span class="info-label">Gun Drop Eligible:</span>
                                    <span class="info-value">${content.gunDropEligible || 'No'}</span>
                                </div>
                                <div class="info-row">
                                    <span class="info-label">Next Gun Drop:</span>
                                    <span class="info-value" id="gun-drop-timer" style="color:${cdColor};font-weight:600;">${cdDisplay}</span>
                                </div>
                            </div>
                        </div>
                    `;
                    if (cdSecs > 0) {
                        let secsLeft = cdSecs;
                        const timerEl = tabContent.querySelector('#gun-drop-timer');
                        const iid = setInterval(function() {
                            secsLeft--;
                            if (!timerEl || !document.body.contains(timerEl)) { clearInterval(iid); return; }
                            if (secsLeft <= 0) {
                                clearInterval(iid);
                                timerEl.textContent = 'Available Now';
                                timerEl.style.color = '#22c55e';
                            } else {
                                timerEl.textContent = formatTimeRemaining(secsLeft);
                            }
                        }, 1000);
                        if (!window.cooldownIntervals) window.cooldownIntervals = [];
                        window.cooldownIntervals.push(iid);
                    }
                } else {
                    renderOverview();
                }
            }
        }
    });
})();
