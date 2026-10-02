package com.adib.crm.admin.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfig {

    // ── ADD / REMOVE USERS HERE ─────────────────────────────────────────────
    // Roles: ADMIN = full access, VIEWER = read-only (no save/delete buttons)
    @Bean
    public UserDetailsService users(PasswordEncoder encoder) {
        return new InMemoryUserDetailsManager(

            User.withUsername("crmadmin")
                .password(encoder.encode("Adib@CRM2024"))
                .roles("ADMIN")
                .build(),

            User.withUsername("tajudeen")
                .password(encoder.encode("Adib@2024!"))
                .roles("ADMIN")
                .build(),

            User.withUsername("viewer1")
                .password(encoder.encode("View@2024"))
                .roles("VIEWER")
                .build()

            // To add more users, copy one block above and change username/password
        );
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/**").authenticated()
                .anyRequest().authenticated()
            )
            .formLogin(form -> form
                .loginPage("/login")
                .defaultSuccessUrl("/", true)
                .permitAll()
            )
            .logout(logout -> logout
                .logoutSuccessUrl("/login?logout")
                .permitAll()
            )
            .csrf(csrf -> csrf.disable()); // disabled for REST API calls
        return http.build();
    }
}
